// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os
import time
import tools.packages.pkgprotocol

fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)
fn C.link(&char, &char) int
fn C.mkfifo(&char, u32) int
#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
struct MirrorAdmissionLimit { current u64 maximum u64 }

fn mirror_fixture() !(string, Config, []Package) {
	work := os.real_path(os.temp_dir()) + '/vinix-mirror-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/repository/objects')!
	key := keygen(work + '/seed')!
	app_bytes := 'application payload'
	data_bytes := 'shared data payload'
	app_file := Payload{ path: 'bin/app', bytes: u64(app_bytes.len), sha256: sha256.sum(app_bytes.bytes()).hex(), executable: true }
	data_file := Payload{ path: 'share/data', bytes: u64(data_bytes.len), sha256: sha256.sum(data_bytes.bytes()).hex() }
	packages := [
		Package{ id: 'app', version: '1.0.0', architecture: 'aarch64', name: 'Application', license: 'MIT',
			kind: 'native', entrypoint: 'bin/app', dependencies: [Dependency{ id: 'data' }],
			files: [app_file, Payload{ ...app_file, path: 'bin/copy' }] },
		Package{ id: 'data', version: '1.0.0', architecture: 'all', name: 'Data', license: 'MIT',
			kind: 'data', files: [data_file] },
	]
	os.mkdir_all(work + '/repository/manifests')!
	for p in packages { os.write_file(work + '/repository/manifests/' + p.id + '.json', json2.encode(p))! }
	os.write_file(work + '/repository/objects/' + app_file.sha256, app_bytes)!
	os.write_file(work + '/repository/objects/' + data_file.sha256, data_bytes)!
	publish(work + '/repository', 'fixture', work + '/seed', 1, time.now().unix() + 3600)!
	config := Config{ architecture: 'aarch64',
		repositories: [Repository{ id: 'fixture', url: 'file://' + work + '/repository', public_key: key }],
		policy: Policy{ reserve_bytes: 0 } }
	refresh(config, work + '/store')!
	return work, config, packages
}

fn mirror_stages(parent string) ![]string {
	return os.ls(parent)!.filter(it.starts_with('.vinix-mirror-'))
}

fn test_mirror_private_publication_verified_closure_and_ordinary_reader_modes() {
	work, config, packages := mirror_fixture()!
	defer { os.rmdir_all(work) or {} }
	store := work + '/store'
	plan := resolve(load_catalog(config, store)!, config, State{}, ['app'], true)!
	exported, acquired := mirror_space(plan, read_snapshots(store)!, store)!
	assert exported == u64(4 * 1024 * 1024 + 3 * 8192)
		+ os.file_size(work + '/repository/index.json') + os.file_size(work + '/repository/index.sig') - 1
		+ packages[0].files[0].bytes + packages[1].files[0].bytes
	assert acquired == packages[0].files[0].bytes + packages[1].files[0].bytes + 2 * 8192
	mirror(config, store, work + '/export', ['app'])!
	assert mirror_stages(work)!.len == 0
	assert os.read_file(work + '/export/fixture/index.json')! == os.read_file(work + '/repository/index.json')!
	assert os.read_file(work + '/export/fixture/index.sig')!.trim_space() == os.read_file(work + '/repository/index.sig')!.trim_space()
	assert os.ls(work + '/export/fixture/objects')!.len == 2
	for p in packages {
		for file in p.files {
			path := work + '/export/fixture/objects/' + file.sha256
			assert verified_file(path, file) && os.stat(path)!.mode & 0o777 == 0o644
		}
	}
	assert os.stat(work + '/export')!.mode & 0o777 == 0o755
	_, cache_after := mirror_space(plan, read_snapshots(store)!, store)!
	assert cache_after == 0 && read_state(store, 'aarch64')!.generation == 0
	// Remove the upstream entirely: a fresh installation consumes only the mirror.
	os.rmdir_all(work + '/repository')!
	offline := Config{ ...config, repositories: [Repository{ ...config.repositories[0], url: 'file://' + work + '/export/fixture' }],
		policy: Policy{ offline: true, reserve_bytes: 0 } }
	refresh(offline, work + '/offline')!
	state := transact(offline, work + '/offline', 'install', ['app'], TransactionOptions{})!
	assert state.packages.len == 2 && state.requested == ['app']
	assert state.packages.map(it.package) == packages
}

fn test_mirror_failed_acquisition_cleans_stage_and_retry_reuses_verified_cache() {
	work, config, packages := mirror_fixture()!
	defer { os.rmdir_all(work) or {} }
	missing := work + '/repository/objects/' + packages[1].files[0].sha256
	bytes := os.read_file(missing)!
	os.rm(missing)!
	mut failed := false
	mirror(config, work + '/store', work + '/export', ['app']) or { failed = err.msg().contains('unavailable') }
	assert failed && !os.exists(work + '/export') && mirror_stages(work)!.len == 0
	assert verified_file(work + '/store/objects/' + packages[0].files[0].sha256, packages[0].files[0])
	os.rm(work + '/repository/objects/' + packages[0].files[0].sha256)!
	os.write_file(missing, bytes)!
	mirror(config, work + '/store', work + '/export', ['app'])!
	assert os.ls(work + '/export/fixture/objects')!.len == 2
	assert read_state(work + '/store', 'aarch64')!.generation == 0
}

fn mirror_corrupt_copy(phase string, path string) ! {
	if phase == 'copied' { os.write_file(path, 'application payloaX')! }
}

fn mirror_collide_at_publication(phase string, stage string) ! {
	if phase != 'ready' { return }
	os.mkdir(os.dir(stage) + '/collision')!
}

fn mirror_interrupt_ready(phase string, _ string) ! {
	if phase == 'ready' { C._exit(77) }
}

fn mirror_no_space(_ string) !u64 { return 0 }

fn test_mirror_corruption_and_destination_races_never_publish_or_replace() {
	work, config, _ := mirror_fixture()!
	defer { os.rmdir_all(work) or {} }
	mut refused := false
	mirror_export(config, work + '/store', work + '/corrupt', ['app'], MirrorOptions{ checkpoint: mirror_corrupt_copy }) or {
		refused = err.msg().contains('mirror payload verification failed')
	}
	assert refused && !os.exists(work + '/corrupt') && mirror_stages(work)!.len == 0
	refused = false
	mirror_export(config, work + '/store', work + '/collision', ['app'], MirrorOptions{ checkpoint: mirror_collide_at_publication }) or {
		refused = err.msg().contains('without replacing')
	}
	assert refused && os.is_dir(work + '/collision') && os.ls(work + '/collision')!.len == 0
	assert mirror_stages(work)!.len == 0
	for target in [work + '/collision', work + '/file', work + '/link'] {
		if target.ends_with('/file') { os.write_file(target, 'keep me')! }
		if target.ends_with('/link') { os.symlink(work + '/absent', target)! }
		refused = false
		mirror(config, work + '/store', target, ['app']) or { refused = err.msg().contains('must be new') }
		assert refused
	}
	assert os.read_file(work + '/file')! == 'keep me'
	assert os.readlink(work + '/link')! == work + '/absent'
	os.mkdir(work + '/unsafe')!
	os.chmod(work + '/unsafe', 0o777)!
	refused = false
	mirror(config, work + '/store', work + '/unsafe/export', ['app']) or {
		refused = err.msg().contains('parent must be controlled')
	}
	assert refused && !os.exists(work + '/unsafe/export')
	assert os.ls(work + '/unsafe')!.len == 0
	os.chmod(work + '/unsafe', 0o1777)!
	mirror(config, work + '/store', work + '/unsafe/nested/export', ['app'])!
	assert os.is_dir(work + '/unsafe/nested/export')
}

fn test_mirror_space_preflight_and_abrupt_exit_leave_final_name_retryable() {
	work, config, _ := mirror_fixture()!
	defer { os.rmdir_all(work) or {} }
	mut refused := false
	mirror_export(config, work + '/store', work + '/full', ['app'], MirrorOptions{ available_space: mirror_no_space }) or {
		refused = err.msg().contains('insufficient disk space')
	}
	assert refused && !os.exists(work + '/full') && mirror_stages(work)!.len == 0
	assert os.ls(work + '/store/objects')!.len == 0
	pid := C.fork()
	assert pid >= 0
	if pid == 0 {
		mirror_export(config, work + '/store', work + '/interrupted', ['app'], MirrorOptions{ checkpoint: mirror_interrupt_ready }) or { C._exit(78) }
		C._exit(79)
	}
	mut status := 0
	assert C.waitpid(pid, &status, 0) == pid && status == 77 << 8
	assert !os.exists(work + '/interrupted') && mirror_stages(work)!.len == 1
	// A retry never reuses unauthenticated staging data or sweeps unrelated trees.
	os.rmdir_all(work + '/repository')!
	mirror(config, work + '/store', work + '/interrupted', ['app'])!
	assert os.is_dir(work + '/interrupted') && mirror_stages(work)!.len == 1
	refused = false
	mirror_cost(~u64(0), 1) or { refused = true }
	assert refused
}

fn mirror_service() !(string, Service, Config, []Package) {
	work, config, packages := mirror_fixture()!
	root := work + '/client'
	os.mkdir_all(root + '/etc/vinix-packages')!
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(config))!
	os.mkdir_all(os.dir(state_directory(root)))!
	os.rename(work + '/store', state_directory(root))!
	return work, Service{ root: root }, config, packages
}

fn test_mirror_review_is_read_only_and_binds_destination_policy_and_signed_metadata() {
	work, service, config, _ := mirror_service()!
	defer { os.rmdir_all(work) or {} }
	store := state_directory(service.root)
	destination := work + '/missing/media/export; $literal'
	mut review := service.review_mirror(destination, ['app'])!
	defer { review.close() }
	assert review.review.operation == 'mirror' && review.review.rows.map(it.action) == ['export', 'export']
	assert review.review.rows.map(it.id) == ['app', 'data'] && review.review.requested == ['app']
	assert review.review.rows.all(it.public_key == config.repositories[0].public_key)
	assert review.destination == destination && review.input_destination == destination
	assert review.shared_disk && review.cache_needed > 0 && review.review.disk_needed > review.cache_needed
	assert !os.exists(work + '/missing') && os.ls(store + '/objects')!.len == 0
	assert read_state(store, 'aarch64')!.generation == 0
	for target in [work + '/different/export', destination] {
		mut refused := false
		service.apply_mirror(target, ['data'], review.review.fingerprint) or { refused = err.msg().contains('stale') }
		assert refused && !os.exists(os.dir(target)) && os.ls(store + '/objects')!.len == 0
	}
	changed := Config{ ...config, policy: Policy{ ...config.policy, reserve_bytes: 1 } }
	os.write_file(service.root + '/etc/vinix-packages/config.json', json2.encode(changed))!
	mut refused := false
	service.apply_mirror(destination, ['app'], review.review.fingerprint) or { refused = err.msg().contains('stale') }
	assert refused && !os.exists(work + '/missing')
	os.write_file(service.root + '/etc/vinix-packages/config.json', json2.encode(config))!
	publish(work + '/repository', 'fixture', work + '/seed', 2, time.now().unix() + 3600)!
	service.refresh()!
	refused = false
	service.apply_mirror(destination, ['app'], review.review.fingerprint) or { refused = err.msg().contains('stale') }
	assert refused && !os.exists(work + '/missing') && os.ls(store + '/objects')!.len == 0
	mut fresh := service.review_mirror(destination, ['app'])!
	defer { fresh.close() }
	service.apply_mirror(destination, ['app'], fresh.review.fingerprint)!
	assert os.ls(destination + '/fixture/objects')!.len == 2 && read_state(store, 'aarch64')!.generation == 0
}

fn test_mirror_review_refuses_replaced_media_and_cross_command_fingerprints() {
	work, service, _, _ := mirror_service()!
	defer { os.rmdir_all(work) or {} }
	os.mkdir(work + '/media')!
	mut review := service.review_mirror(work + '/media/export', ['app'])!
	defer { review.close() }
	os.rename(work + '/media', work + '/old-media')!
	os.mkdir(work + '/media')!
	mut refused := false
	service.apply_mirror(work + '/media/export', ['app'], review.review.fingerprint) or { refused = err.msg().contains('stale') }
	assert refused && os.ls(work + '/media')!.len == 0
	mut ordinary := service.review('install', ['app'])!
	defer { ordinary.close() }
	refused = false
	service.apply_mirror(work + '/media/export', ['app'], ordinary.fingerprint) or { refused = err.msg().contains('stale') }
	assert refused && os.ls(state_directory(service.root) + '/objects')!.len == 0
	guard := acquire(state_directory(service.root))!
	defer { guard.release() }
	refused = false
	service.review_mirror(work + '/never/create/export', ['app']) or { refused = err.msg().contains('another package transaction') }
	assert refused && !os.exists(work + '/never')
}

fn mirror_report(event pkgprotocol.Progress) {
	event.validate() or { panic(err) }
	path := os.getenv('VINIX_MIRROR_PROGRESS_TEST')
	defer { unsafe { path.free() } }
	mut file := os.open_file(path, 'a') or { panic(err) }
	defer { file.close() }
	file.writeln(json2.encode(event)) or { panic(err) }
}

fn test_mirror_progress_and_cache_recovery_do_not_invalidate_review_or_complete_on_failure() {
	work, service, config, packages := mirror_service()!
	defer { os.unsetenv('VINIX_MIRROR_PROGRESS_TEST'); os.rmdir_all(work) or {} }
	os.write_file(work + '/events', '')!
	os.setenv('VINIX_MIRROR_PROGRESS_TEST', work + '/events', true)
	mut review := service.review_mirror(work + '/export', ['app'])!
	defer { review.close() }
	missing := work + '/repository/objects/' + packages[1].files[0].sha256
	data := os.read_file(missing)!
	os.rm(missing)!
	observed := Service{ ...service, progress: mirror_report }
	mut failed := false
	observed.apply_mirror(work + '/export', ['app'], review.review.fingerprint) or { failed = true }
	assert failed && !os.exists(work + '/export') && mirror_stages(work)!.len == 0
	for line in os.read_file(work + '/events')!.split_into_lines() {
		assert pkgprotocol.decode_progress(line)!.phase != 'complete'
	}
	os.write_file(missing, data)!
	os.rm(work + '/repository/objects/' + packages[0].files[0].sha256)!
	os.write_file(work + '/events', '')!
	observed.apply_mirror(work + '/export', ['app'], review.review.fingerprint)!
	mut events := []pkgprotocol.Progress{}
	for line in os.read_file(work + '/events')!.split_into_lines() { events << pkgprotocol.decode_progress(line)! }
	assert events.first().phase == 'resolve' && events.last().phase == 'complete'
	assert events.any(it.phase == 'copy' && it.current == it.total)
	assert events.any(it.phase == 'verify') && events.any(it.phase == 'download' && it.package == 'data')
	assert events.all(it.phase != 'activate')
	assert read_state(state_directory(service.root), config.architecture)!.generation == 0
}

fn mirror_change_ready(phase string, stage string) ! {
	if phase != 'ready' { return }
	path := stage + '/fixture/index.json'
	os.write_file(path, 'changed after copying')!
}

fn test_mirror_late_metadata_change_refuses_publication_and_retries_verified_cache() {
	work, config, packages := mirror_fixture()!; defer { os.rmdir_all(work) or {} }
	destination := work + '/export'
	mut message := ''
	mirror_export(config, work + '/store', destination, ['app'], MirrorOptions{ checkpoint: mirror_change_ready }) or { message = err.msg() }
	println('MIRROR ADMISSION late-index refused=' + message.contains('offline mirror verification').str() + ' unpublished=' + (!os.exists(destination)).str())
	assert message.contains('offline mirror verification') && !os.exists(destination)
	assert mirror_stages(work)!.len == 0 && read_state(work + '/store', 'aarch64')!.generation == 0
	for p in packages { for file in p.files { assert verified_file(work + '/store/objects/' + file.sha256, file) } }
	os.rmdir_all(work + '/repository')!
	mirror(config, work + '/store', destination, ['app'])!
	assert os.read_file(destination + '/fixture/index.json')! != 'changed after copying'
	println('MIRROR ADMISSION changed staged metadata refuses before publication; verified cache survives and offline retry succeeds PASS')
}

fn mirror_admission_mutate(phase string, input string) ! {
	if phase != os.getenv('VINIX_MIRROR_ADMISSION_PHASE') { return }
	work := os.getenv('VINIX_MIRROR_ADMISSION_WORK')
	if os.exists(work + '/mutated') { return }
	stage := if phase == 'copied' { os.dir(os.dir(os.dir(input))) } else { input }
	subject := os.getenv('VINIX_MIRROR_ADMISSION_SUBJECT')
	kind := os.getenv('VINIX_MIRROR_ADMISSION_KIND')
	path := stage + '/' + subject
	os.write_file(work + '/mutated', 'once')!
	match kind {
		'extra' { os.write_file(path + '/unrequested', 'unreviewed object')! }
		'mode' { os.chmod(path, if os.is_dir(path) { 0o700 } else { 0o600 })! }
		'link' { assert C.link(path.str, (work + '/linked').str) == 0 }
		'rewrite' { os.write_file(path, 'changed after copy')! }
		else {
			os.rename(path, work + '/saved')!
			match kind {
				'alias' { os.symlink(work + '/outside', path)! }
				'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
				'dir-alias' { os.symlink(work + '/outside-dir', path)! }
				'missing' {}
				else { panic('unknown mirror admission mutation') }
			}
		}
	}
}

fn test_mirror_whole_stage_refuses_late_changes_and_unreviewed_namespace_without_completion() {
	work, config, packages := mirror_fixture()!; defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/outside', 'preserved')!; os.chmod(work + '/outside', 0o600)!
	os.mkdir(work + '/outside-dir')!; os.chmod(work + '/outside-dir', 0o700)!
	os.write_file(work + '/outside-dir/keep', 'preserved')!
	os.setenv('VINIX_MIRROR_ADMISSION_WORK', work, true)
	os.setenv('VINIX_MIRROR_PROGRESS_TEST', work + '/events', true)
	defer { for name in ['VINIX_MIRROR_ADMISSION_WORK', 'VINIX_MIRROR_ADMISSION_PHASE', 'VINIX_MIRROR_ADMISSION_SUBJECT', 'VINIX_MIRROR_ADMISSION_KIND', 'VINIX_MIRROR_PROGRESS_TEST'] { os.unsetenv(name) } }
	store := work + '/store'
	catalog := os.read_file(store + '/catalog.json')!; history := os.read_file(store + '/trust-history.json')!
	mut cases := 0
	for phase in ['copied', 'ready'] {
		mut subjects := ['fixture/index.json', 'fixture/index.sig', '']
		if phase == 'ready' { subjects << ['fixture/objects/' + packages[0].files[0].sha256, 'fixture', 'fixture/objects'] }
		for subject in subjects {
			kinds := if subject == '' { ['extra'] }
				else if subject in ['fixture', 'fixture/objects'] { ['extra', 'missing', 'dir-alias', 'mode'] }
				else if phase == 'copied' { ['rewrite', 'missing', 'alias'] }
				else { ['rewrite', 'missing', 'alias', 'fifo', 'link', 'mode'] }
			for kind in kinds {
				for key, value in {'VINIX_MIRROR_ADMISSION_PHASE': phase, 'VINIX_MIRROR_ADMISSION_SUBJECT': subject, 'VINIX_MIRROR_ADMISSION_KIND': kind} { os.setenv(key, value, true) }
				os.write_file(work + '/events', '')!
				mut message := ''
				mirror_export(config, store, work + '/export', ['app'], MirrorOptions{ checkpoint: mirror_admission_mutate, progress: mirror_report }) or { message = err.msg() }
				assert message.contains('offline mirror verification') && !os.exists(work + '/export'), phase + '/' + subject + '/' + kind + ': ' + message
				assert os.exists(work + '/mutated') && mirror_stages(work)!.len == 0
				for line in os.read_file(work + '/events')!.split_into_lines() { assert pkgprotocol.decode_progress(line)!.phase != 'complete' }
				assert os.read_file(store + '/catalog.json')! == catalog && os.read_file(store + '/trust-history.json')! == history
				assert read_state(store, 'aarch64')!.generation == 0 && os.read_file(work + '/outside')! == 'preserved'
				assert os.lstat(work + '/outside')!.mode & 0o777 == 0o600 && os.lstat(work + '/outside-dir')!.mode & 0o777 == 0o700
				assert os.read_file(work + '/outside-dir/keep')! == 'preserved'
				for name in ['mutated', 'linked', 'saved'] {
					path := work + '/' + name
					if os.is_dir(path) { os.rmdir_all(path)! } else if os.exists(path) { os.rm(path)! }
				}
				cases++
			}
		}
	}
	assert cases == 34
	os.rmdir_all(work + '/repository')!
	mirror(config, store, work + '/export', ['app'])!
	assert os.ls(work + '/export/fixture/objects')!.len == 2
	println('MIRROR ADMISSION 34 late metadata/payload/mode/link/namespace refusals preserve source state, outside data and cache; no completion, clean staging and offline retry PASS')
}

fn test_mirror_stage_admission_retires_descriptors_and_accepts_only_the_exported_closure() {
	work, config, _ := mirror_fixture()!; defer { os.rmdir_all(work) or {} }
	mirror(config, work + '/store', work + '/export', ['app'])!
	prepared := prepare_mirror(config, work + '/store', work + '/unused', ['app'])!
	mut original := MirrorAdmissionLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limit := MirrorAdmissionLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limit)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	for _ in 0 .. 128 { verify_mirror_stage(work + '/export', prepared, true)! }
	os.write_file(work + '/export/fixture/unrequested', 'extra')!
	for _ in 0 .. 128 {
		mut refused := false
		verify_mirror_stage(work + '/export', prepared, true) or {
			message := err.msg(); refused = message.contains('unexpected export entry')
			unsafe { message.free(); err.free() }
		}
		assert refused
	}
	os.rm(work + '/export/fixture/unrequested')!
	verify_mirror_stage(work + '/export', prepared, true)!
	println('MIRROR ADMISSION 128 valid and refused complete-stage scans retire descriptors under a 32-descriptor limit and restored namespace retries PASS')
}
