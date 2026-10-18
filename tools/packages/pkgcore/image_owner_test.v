// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
fn C.setenv(&char, &char, int) int
struct ImageOwnerLimit { current u64 maximum u64 }
struct ImageOwnerRequirements { format int = 1 architecture string packages []string }

$if track_heap ? {
#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32
}

fn image_owner_fixture(architecture string) !string {
	work := os.real_path(os.temp_dir()) + '/vinix-image-owner-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/source')!; os.mkdir(work + '/image')!; os.mkdir(work + '/scratch')!
	os.write_file(work + '/seed', '00'.repeat(32) + '\n')!; os.chmod(work + '/seed', 0o600)!
	key := key_public(work + '/seed')!
	for repository in ['native', 'support']! {
		for host in if repository == 'native' { ['aarch64', 'x86_64', 'all'] } else { ['all'] } {
			application := host != 'all'; bytes := if application { 'application ' + host } else { 'explicit license document' }
			os.write_file(work + '/source/data', bytes)!; os.chmod(work + '/source/data', if application { 0o755 } else { 0o644 })!
			p := Package{ id: if application { 'app' } else if repository == 'native' { 'license' } else { 'support' },
				name: 'Image fixture', version: '1.0.0', architecture: host, kind: if application { 'native' } else { 'data' },
				entrypoint: if application { 'data' } else { '' }, permissions: if application { ['files'] } else { []string{} },
				license: if application { 'MIT' } else { 'Vendor-EULA' }, proprietary: !application, firmware: !application,
				dependencies: if application { [Dependency{ id: 'license', before: '2.0.0' }] } else { []Dependency{} } }
			os.write_file(work + '/manifest.json', publisher_json(p))!
			mut packed := pack(work + '/manifest.json', work + '/source', work + '/workspace-' + repository)!; packed.close()
		}
		mut info := publish_release(work + '/workspace-' + repository, repository, work + '/seed', 1, 2100000000, work + '/bundle/' + repository)!; info.close()
		for name in ['index.json', 'index.sig']! { os.cp(work + '/bundle/' + repository + '/' + name, work + '/' + repository + '-' + name)! }
	}
	config := Config{ architecture: architecture, policy: Policy{ offline: true, licenses: ['Vendor-EULA'], allow_firmware: true, permissions: ['network', 'files'], reserve_bytes: 0 },
		repositories: [Repository{ id: 'native', public_key: key, url: 'file://' + image_repositories_path + '/native' },
			Repository{ id: 'support', public_key: key, url: 'file://' + image_repositories_path + '/support' }] }
	os.write_file(work + '/original-config.json', publisher_json(config))!; os.cp(work + '/original-config.json', work + '/config.json')!
	os.write_file(work + '/requirements.json', publisher_json(ImageOwnerRequirements{ architecture: architecture, packages: ['app'] }))!
	return work
}

fn image_owner_selected(mode string, architecture string) bool {
	if os.args.len == 1 { return true }; assert os.args.len == 4 && os.args[1] == 'case'
	return mode == os.args[2] && architecture == os.args[3]
}

fn image_owner_descriptors() int {
	mut count := 0; for fd in 0 .. 256 { if C.fcntl(fd, C.F_GETFD, 0) >= 0 { count++ } }; return count
}

fn image_owner_write(path string, text string) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC | C.O_CLOEXEC | C.O_NOFOLLOW, 0o644)
	if fd < 0 { return error('cannot write image owner fixture') }; defer { C.close(fd) }
	assert C.write(fd, text.str, usize(text.len)) == text.len
}

fn image_owner_temporary() string {
	work := os.getenv('VINIX_IMAGE_OWNER_WORK'); defer { unsafe { work.free() } }; return work + '/scratch'
}

fn image_owner_space(path string) !u64 {
	mode := os.getenv('VINIX_IMAGE_OWNER_MODE'); defer { unsafe { mode.free() } }
	if mode == 'space-error' { return error('injected image space refusal') }
	if (mode == 'no-output-space' && !path.ends_with('/scratch')) || (mode == 'no-temp-space' && path.ends_with('/scratch')) { return 0 }
	return ~u64(0)
}

fn image_owner_flush(fd int) int {
	mode := os.getenv('VINIX_IMAGE_OWNER_MODE'); defer { unsafe { mode.free() } }
	if mode == 'flush' { return -1 }; return atomic_flush(fd)
}

fn image_owner_checkpoint(phase string, stage string) ! {
	mode := os.getenv('VINIX_IMAGE_OWNER_MODE'); work := os.getenv('VINIX_IMAGE_OWNER_WORK')
	defer { unsafe { mode.free(); work.free() } }
	if mode == phase { return error('injected image checkpoint refusal') }
	if phase == 'captured' { assert C.setenv(c'VINIX_IMAGE_OWNER_CAPTURE', stage.str, 1) == 0 }
	if phase == 'captured' && mode == 'changed-source' {
		path := work + '/bundle/native/index.json'; defer { unsafe { path.free() } }; image_owner_write(path, '{}')!
	}
	if phase == 'captured' && mode == 'captured-index' {
		path := stage + '/native/index.json'; defer { unsafe { path.free() } }; image_owner_write(path, '{}')!
	}
	if (phase == 'captured' && mode == 'capture-replaced') || (phase == 'staged' && mode == 'stage-replaced') {
		saved := work + '/saved-stage'; keep := stage + '/keep'; defer { unsafe { saved.free(); keep.free() } }
		assert C.rename(stage.str, saved.str) == 0; assert C.mkdir(stage.str, 0o700) == 0; image_owner_write(keep, 'preserved replacement')!
	}
	if phase != 'staged' { return }
	if mode == 'staged-object' {
		hash := index_digest('explicit license document'); path := stage + '/support/objects/' + hash
		defer { unsafe { hash.free(); path.free() } }; image_owner_write(path, 'changed')!
	}
	if mode == 'raced-target' {
		path := work + '/image' + image_repositories_path; keep := path + '/keep'; defer { unsafe { path.free(); keep.free() } }
		assert C.mkdir(path.str, 0o755) == 0; image_owner_write(keep, 'preserved replacement')!
	}
	if mode == 'changed-config' {
		etc := work + '/image/etc'; directory := etc + '/vinix-packages'; path := directory + '/config.json'
		defer { unsafe { etc.free(); directory.free(); path.free() } }
		assert C.mkdir(etc.str, 0o755) == 0; assert C.mkdir(directory.str, 0o755) == 0; image_owner_write(path, '{}')!
	}
	if mode == 'changed-root' {
		root := work + '/image'; saved := work + '/saved-image'; keep := root + '/keep'; defer { unsafe { root.free(); saved.free(); keep.free() } }
		assert C.rename(root.str, saved.str) == 0; assert C.mkdir(root.str, 0o755) == 0; image_owner_write(keep, 'preserved replacement')!
	}
}

fn image_owner_run(work string, architecture string, mode string) ! {
	root := work + '/image'; source := work + '/config.json'; bundle := work + if mode == 'alias-source' { '/alias' } else if mode == 'missing-source' { '/missing' } else { '/bundle' }
	requirements := work + '/requirements.json'; output := work + '/deployment.json'
	defer { unsafe { root.free(); source.free(); bundle.free(); requirements.free(); output.free() } }
	mut configuration := prepare_image_configuration(root, architecture, source)!; defer { configuration.close() }
	options := ImageRepositoriesOptions{ temporary_directory: image_owner_temporary, available_space: image_owner_space, checkpoint: image_owner_checkpoint, flush: image_owner_flush }
	mut repositories := unsafe { &configuration }.prepare_repositories_with(if mode == 'empty-bundle' { '' } else { bundle }, options)!
	defer { repositories.close() }
	if mode == 'empty-bundle' {
		report := unsafe { &configuration }.check_repositories(unsafe { &repositories })!; unsafe { report.free() }
		assert !unsafe { &repositories }.publish()!; assert unsafe { &configuration }.publish()!; repositories.retire()!; return
	}
	if mode == 'export' {
		report := unsafe { &configuration }.export_application_file(unsafe { &repositories }, requirements, output)!; unsafe { report.free() }
		repositories.retire()!; return
	}
	mut applications := unsafe { &configuration }.prepare_application_file(unsafe { &repositories }, requirements)!; defer { applications.close() }
	report := unsafe { &applications }.report(); unsafe { report.free() }
	if mode == 'check-only' { repositories.retire()!; return }
	if mode == 'unsafe-retire' { assert C.chmod(repositories.capture.str, 0o777) == 0; repositories.retire()!; return }
	_ = unsafe { &repositories }.publish_with(options)!
	_ = unsafe { &configuration }.publish()!
	_ = unsafe { &applications }.publish(unsafe { &repositories })!
	repositories.retire()!; repositories.close(); applications.close(); configuration.close()
}

fn image_owner_attempt(work string, architecture string, mode string) {
	if _ := image_owner_run(work, architecture, mode) { assert mode in ['complete', 'check-only', 'preserve', 'export', 'existing-config', 'empty-bundle', 'changed-source']! }
	else {
		message := err.msg(); defer { unsafe { message.free(); err.free() } }
		assert mode !in ['complete', 'check-only', 'preserve', 'export', 'existing-config', 'empty-bundle', 'changed-source']!
		expected := match mode {
			'invalid-config' { 'incomplete package metadata' } 'wrong-architecture' { 'another architecture' }
			'missing-source', 'alias-source' { 'prepared root' } 'unsafe-source' { 'stable owned directory' }
			'wrong-key', 'second-index' { 'signature verification failed' } 'missing-object' { 'missing entries' }
			'deny-license' { 'accept license' } 'deny-firmware' { 'firmware' } 'deny-permission' { 'permissions blocked' }
			'no-output-space', 'no-temp-space' { 'insufficient disk space' } 'space-error' { 'injected image space' }
			'captured', 'staged' { 'injected image checkpoint' } 'captured-index' { 'metadata changed' } 'staged-object' { 'payload changed' }
			'capture-replaced', 'stage-replaced' { 'cleanup refused' } 'unsafe-retire' { 'capture cleanup refused' }
			'flush' { 'published at ' } 'raced-target' { 'without replacing' } 'changed-config' { 'configuration' }
			'changed-root' { 'changed' } 'existing-different' { 'unexpected export entry' } else { panic(mode) }
		}
		assert message.contains(expected), message
	}
}

fn image_owner_remove(path string) ! {
	if os.is_dir(path) && !os.is_link(path) { os.rmdir_all(path)! } else if os.exists(path) || os.is_link(path) { os.rm(path)! }
}

fn image_owner_reset(work string) ! {
	for name in ['image', 'saved-stage', 'saved-image', 'deployment.json', 'alias', 'scratch']! { image_owner_remove(work + '/' + name)! }
	os.mkdir(work + '/image')!; os.mkdir(work + '/scratch')!
	os.chmod(work + '/bundle', 0o755)!; os.cp(work + '/original-config.json', work + '/config.json')!
	for repository in ['native', 'support']! {
		for name in ['index.json', 'index.sig']! { os.cp(work + '/' + repository + '-' + name, work + '/bundle/' + repository + '/' + name)! }
	}
	os.write_file(work + '/bundle/support/objects/' + index_digest('explicit license document'), 'explicit license document')!
}

fn image_owner_prepare(work string, architecture string, mode string) ! {
	path := work + '/config.json'; text := os.read_file(path)!
	match mode {
		'invalid-config' { os.write_file(path, '{')! }
		'wrong-architecture' { os.write_file(path, text.replace(architecture, if architecture == 'aarch64' { 'x86_64' } else { 'aarch64' }))! }
		'wrong-key' { os.write_file(path, text.replace(key_public(work + '/seed')!, signing_seed_public([]u8{len: 32, init: 1})))! }
		'alias-source' { os.symlink(work + '/bundle', work + '/alias')! }
		'unsafe-source' { os.chmod(work + '/bundle', 0o777)! }
		'second-index' { os.write_file(work + '/bundle/support/index.json', '{}')! }
		'missing-object' { os.rm(work + '/bundle/support/objects/' + index_digest('explicit license document'))! }
		'deny-license' { os.write_file(path, text.replace('"licenses":["Vendor-EULA"]', '"licenses":[]'))! }
		'deny-firmware' { os.write_file(path, text.replace('"allow_firmware":true', '"allow_firmware":false'))! }
		'deny-permission' { os.write_file(path, text.replace('"permissions":["network","files"]', '"permissions":[]'))! }
		'existing-config' { os.mkdir_all(work + '/image/etc/vinix-packages')!; os.cp(path, work + '/image/etc/vinix-packages/config.json')! }
		'preserve' { image_owner_run(work, architecture, 'complete')! }
		'existing-different' { os.mkdir_all(work + '/image' + image_repositories_path)!; os.write_file(work + '/image' + image_repositories_path + '/keep', 'preserved replacement')! }
		else {}
	}
}

fn test_image_inputs_retain_no_call_storage_across_capture_report_publication_and_retirement() {
	defer { for name in ['MODE', 'WORK', 'CAPTURE']! { os.unsetenv('VINIX_IMAGE_OWNER_' + name) } }
	for architecture in ['aarch64', 'x86_64']! {
		for mode in ['complete', 'check-only', 'preserve', 'export', 'existing-config', 'empty-bundle', 'invalid-config', 'wrong-architecture', 'missing-source', 'alias-source',
			'unsafe-source', 'wrong-key', 'second-index', 'missing-object', 'deny-license', 'deny-firmware', 'deny-permission', 'no-output-space', 'no-temp-space', 'space-error',
			'captured', 'staged', 'changed-source', 'captured-index', 'staged-object', 'capture-replaced', 'stage-replaced', 'unsafe-retire', 'flush', 'raced-target', 'changed-config', 'changed-root', 'existing-different']! {
			if !image_owner_selected(mode, architecture) { continue }
			work := image_owner_fixture(architecture)!; defer { os.rmdir_all(work) or {} }
			os.setenv('VINIX_IMAGE_OWNER_WORK', work, true); os.unsetenv('VINIX_IMAGE_OWNER_MODE')
			image_owner_run(work, architecture, 'complete')!
			golden := os.read_file(work + '/image/usr/share/vinix-packages/applications.json')!
			os.setenv('VINIX_IMAGE_OWNER_MODE', mode, true)
			mut original := ImageOwnerLimit{}; assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
			limited := ImageOwnerLimit{ current: 32, maximum: original.maximum }; assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limited }) == 0
			before := image_owner_descriptors(); mut maximum := u64(0); mut records := u32(0)
			for _ in 0 .. 4 {
				image_owner_reset(work)!; image_owner_prepare(work, architecture, mode)!
				$if track_heap ? { C.vinix_heap_begin() }
				image_owner_attempt(work, architecture, mode)
				$if track_heap ? { kept := C.vinix_heap_end(); count := C.vinix_heap_count(); if kept > maximum { maximum = kept }; if count > records { records = count } }
				assert image_owner_descriptors() == before && !os.exists(work + '/image/var')
				if mode in ['complete', 'preserve', 'existing-config', 'changed-source']! { assert os.read_file(work + '/image/usr/share/vinix-packages/applications.json')! == golden }
				if mode == 'export' { assert os.read_file(work + '/deployment.json')! == golden && os.ls(work + '/image')!.len == 0 }
				if mode == 'check-only' { assert os.ls(work + '/image')!.len == 0 }
				if mode in ['raced-target', 'existing-different']! { assert os.read_file(work + '/image' + image_repositories_path + '/keep')! == 'preserved replacement' }
				if mode == 'changed-root' { assert os.read_file(work + '/image/keep')! == 'preserved replacement' }
				if mode in ['capture-replaced', 'stage-replaced', 'unsafe-retire']! { assert os.is_dir(work + '/saved-stage') || os.ls(work + '/scratch')!.len > 0 }
			}
			assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
			$if track_heap ? { println('IMAGE OWNER arch=' + architecture + ' case=' + mode + ' retained=' + maximum.str() + ' allocations=' + records.str()); $if !image_owner_baseline ? { assert maximum == 0 && records == 0 } }
			image_owner_reset(work)!; os.unsetenv('VINIX_IMAGE_OWNER_MODE'); image_owner_run(work, architecture, 'complete')!
			assert os.read_file(work + '/image/usr/share/vinix-packages/applications.json')! == golden
			assert os.read_file(work + '/bundle/native/index.json')! == os.read_file(work + '/native-index.json')!
			println('IMAGE OWNER ' + architecture + ' ' + mode + ' exact declaration retry, trust, sources, recovery and descriptors PASS')
		}
	}
}
