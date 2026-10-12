// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os
import time

fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)

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
