// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os
import time
import tools.packages.pkgprotocol

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn status_fixture(populated bool) !(string, Service) {
	root := os.temp_dir() + '/vinix-status-owned-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(root + '/etc/vinix-packages')!
	config := Config{ architecture: 'aarch64', policy: Policy{ offline: true, permissions: [], reserve_bytes: 0 } }
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(config))!
	if populated {
		directory := state_directory(root)
		guard := acquire(directory)!; guard.release()
		generation := directory + '/generations/7'
		os.mkdir_all(generation + '/share/applications')!
		mut packages := []Installed{}
		for id in ['app', 'runtime', 'assets']! {
			path := generation + '/apps/' + id + '/bin/app'
			os.mkdir_all(os.dir(path))!; os.write_file(path, 'payload')!; os.chmod(path, if id == 'assets' { 0o644 } else { 0o755 })!
			p := Package{ id: id, name: 'Application é🚀 ' + id, version: '1.0.0', architecture: if id == 'assets' { 'all' } else { 'aarch64' },
				kind: if id == 'runtime' { 'runtime' } else if id == 'assets' { 'data' } else { 'native' }, license: 'MIT',
				entrypoint: if id == 'app' { 'bin/app' } else { '' },
				dependencies: if id == 'app' { [Dependency{ id: 'runtime' }, Dependency{ id: 'assets' }] } else { []Dependency{} },
				files: [Payload{ path: 'bin/app', sha256: sha256.hexhash('payload'), bytes: 7, executable: id != 'assets' }] }
			packages << Installed{ package: p, repository: 'publisher', public_key: 'a'.repeat(64), sequence: 7 }
			if id == 'app' { os.write_file(generation + '/share/applications/vinix-app.desktop', desktop_entry(p))! }
		}
		os.write_file(generation + '/state.json', encode_generation_state(State{ architecture: 'aarch64', generation: 7, requested: ['app'], packages: packages })!)!
		os.symlink('generations/7', directory + '/current')!
		os.write_file(directory + '/catalog.json', '{unavailable catalog')!
		os.write_file(directory + '/trust-history.json', '{unavailable history')!
	}
	return root, Service{ root: root }
}

fn retire_status(mut state State) {
	state.close(); state.close()
	assert state.generation == 0 && state.architecture == '' && state.requested.len == 0 && state.packages.len == 0
}

fn status_read(service Service, verify bool) !State {
	if verify { return service.verify() }
	return service.state()
}

fn status_refusal(service Service, verify bool, expected string) {
	if value := status_read(service, verify) {
		close_decoded_state(value); assert false, 'accepted invalid installed state'
	} else {
		message := err.msg(); assert message.contains(expected), message
		unsafe { message.free(); err.free() }
	}
}

fn test_status_snapshots_retire_fresh_installed_and_failed_verification_storage() {
	$if track_heap ? {
		fresh_root, fresh := status_fixture(false)!; defer { os.rmdir_all(fresh_root) or {} }
		root, service := status_fixture(true)!; defer { os.rmdir_all(root) or {} }
		C.vinix_heap_begin()
		for _ in 0 .. 1000 {
			mut status := fresh.state()!; assert status.generation == 0; retire_status(mut status)
			mut checked := fresh.verify()!; assert checked.architecture == 'aarch64'; retire_status(mut checked)
		}
		fresh_bytes := C.vinix_heap_end()
		C.vinix_heap_begin()
		for _ in 0 .. 1000 {
			mut status := service.state()!; assert status.packages.len == 3; retire_status(mut status)
			mut checked := service.verify()!; assert checked.generation == 7; retire_status(mut checked)
		}
		installed_bytes := C.vinix_heap_end()
		os.write_file(state_directory(root) + '/current/apps/app/bin/app', 'damaged')!
		C.vinix_heap_begin()
		for _ in 0 .. 1000 { status_refusal(service, true, 'installed payload verification failed') }
		failed_bytes := C.vinix_heap_end()
		println('STATUS SNAPSHOT 1000 fresh state/verify cycles retained ${fresh_bytes} bytes; 1000 installed cycles retained ${installed_bytes} bytes; 1000 failed verifies retained ${failed_bytes} bytes')
		assert fresh_bytes == 0 && installed_bytes == 0 && failed_bytes == 0
	}
}

fn test_status_snapshots_own_all_fields_preserve_bytes_and_keep_empty_reads_side_effect_free() {
	for architecture in ['aarch64', 'x86_64']! {
		for populated in [false, true]! {
			root, service := status_fixture(populated)!; defer { os.rmdir_all(root) or {} }
			configuration := root + '/etc/vinix-packages/config.json'
			os.write_file(configuration, os.read_file(configuration)!.replace('aarch64', architecture))!
			store := state_directory(root)
			metadata := store + '/current/state.json'
			if populated { os.write_file(metadata, os.read_file(metadata)!.replace('aarch64', architecture))! }
			config_text := os.read_file(configuration)!
			state_text := if populated { os.read_file(metadata)! } else { '' }
			mut first := service.state()!
			mut second := service.verify()!
			assert first == second && first.architecture == architecture
			assert first.architecture.str != second.architecture.str
			if populated {
				assert first.packages[0].package.files.data != second.packages[0].package.files.data
				assert encode_generation_state(first)! == state_text
				assert os.read_file(metadata)! == state_text && os.readlink(store + '/current')! == 'generations/7'
				assert os.read_file(store + '/catalog.json')! == '{unavailable catalog'
				assert os.read_file(store + '/trust-history.json')! == '{unavailable history'
				assert os.ls(store + '/generations')! == ['7'] && os.ls(store + '/objects')!.len == 0
			} else { assert !os.exists(store) && first.requested.len == 0 && first.packages.len == 0 }
			assert os.read_file(configuration)! == config_text
			retire_status(mut first)
			os.write_file(configuration, '{replaced configuration')!
			if populated { os.write_file(metadata, '{replaced state')! }
			assert second.architecture == architecture
			if populated { assert second.packages[0].package.name == 'Application é🚀 app' && second.packages[0].package.files[0].path == 'bin/app' }
			retire_status(mut second)
		}
	}
	println('STATUS SNAPSHOT both architectures, independent fresh/installed ownership, repeated close, exact state bytes and read-only offline observations PASS')
}

fn status_forbid_progress(_ pkgprotocol.Progress) { panic('status must not scan files or emit verification progress') }

fn status_observe_progress(event pkgprotocol.Progress) {
	root := os.getenv('VINIX_STATUS_TEST_ROOT'); defer { unsafe { root.free() } }
	directory := state_directory(root); defer { unsafe { directory.free() } }
	if guard := acquire(directory) { guard.release(); panic('verification released its reader lock') }
	else { message := err.msg(); assert message.contains('another package transaction'); unsafe { message.free(); err.free() } }
	path := root + '/progress.txt'; defer { unsafe { path.free() } }
	mut file := os.open_append(path) or { panic(err) }; defer { file.close() }
	file.writeln(event.phase + ':' + event.package + ':' + event.path) or { panic(err) }
}

fn test_status_does_not_verify_and_verification_keeps_its_lock_until_completion() {
	root, service := status_fixture(true)!; defer { os.rmdir_all(root) or {} }
	mut state := (Service{ root: root, progress: status_forbid_progress }).state()!; retire_status(mut state)
	os.write_file(root + '/progress.txt', '')!
	os.setenv('VINIX_STATUS_TEST_ROOT', root, true); defer { os.unsetenv('VINIX_STATUS_TEST_ROOT') }
	mut verified := (Service{ root: root, progress: status_observe_progress }).verify()!; retire_status(mut verified)
	assert os.read_file(root + '/progress.txt')! == 'verify::\nverify:app:bin/app\nverify:app:share/applications/vinix-app.desktop\nverify:runtime:bin/app\nverify:assets:bin/app\ncomplete::\n'
	store := state_directory(root)
	os.write_file(store + '/current/apps/app/bin/app', 'damaged')!
	mut observed := service.state()!; assert observed.packages.len == 3; retire_status(mut observed)
	os.write_file(root + '/progress.txt', '')!
	status_refusal(Service{ root: root, progress: status_observe_progress }, true, 'installed payload verification failed')
	assert !os.read_file(root + '/progress.txt')!.contains('complete:')
	println('STATUS SNAPSHOT status skips integrity scans; verify holds its reader lock through progress, refuses damage and emits completion only on success PASS')
}

fn test_status_refusals_retire_configuration_state_and_lock_scratch_before_retry() {
	root, service := status_fixture(true)!; defer { os.rmdir_all(root) or {} }
	store := state_directory(root)
	configuration := root + '/etc/vinix-packages/config.json'; config_text := os.read_file(configuration)!
	metadata := store + '/current/state.json'; state_text := os.read_file(metadata)!
	registration := store + '/current/share/applications/vinix-app.desktop'; entry := os.read_file(registration)!
	for failure in ['configuration', 'state', 'registration', 'namespace', 'activation', 'busy']! {
		mut guard := Lock{ fd: -1 }
		match failure {
			'configuration' { os.write_file(configuration, '{broken configuration')! }
			'state' { os.write_file(metadata, '{broken state')! }
			'registration' { os.write_file(registration, 'damaged')! }
			'namespace' { os.write_file(store + '/current/apps/app/unexpected', 'undeclared')! }
			'activation' { os.rm(store + '/current')!; os.write_file(store + '/current', 'not a pointer')! }
			'busy' { guard = acquire(store)!; os.write_file(configuration, '{must not be read')! }
			else {}
		}
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. 1000 {
			status_refusal(service, true, if failure == 'busy' { 'another package transaction' } else { '' })
			if failure !in ['registration', 'namespace']! { status_refusal(service, false, '') }
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, failure + ' retained bytes: ' + kept.str() }
		match failure {
			'configuration' { os.write_file(configuration, config_text)! }
			'state' { os.write_file(metadata, state_text)! }
			'registration' { os.write_file(registration, entry)! }
			'namespace' { os.rm(store + '/current/apps/app/unexpected')! }
			'activation' { os.rm(store + '/current')!; os.symlink('generations/7', store + '/current')! }
			'busy' { guard.release(); os.write_file(configuration, config_text)! }
			else {}
		}
		mut restored := service.verify()!; assert restored.generation == 7; retire_status(mut restored)
	}
	assert os.read_file(metadata)! == state_text && os.read_file(configuration)! == config_text
	println('STATUS SNAPSHOT 1000-cycle configuration/state/registration/namespace/activation/busy refusals retire scratch and permit restored retry PASS')
}
