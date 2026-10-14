// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

fn C.mkfifo(&char, u32) int

fn state_validation_fixture(architecture string) State {
	runtime := Package{ id: 'runtime', version: '1.0.0', architecture: architecture, name: 'Runtime', license: 'MIT', kind: 'runtime',
		files: [Payload{ path: 'bin/runner', sha256: 'a'.repeat(64), bytes: 1, executable: true }] }
	app := Package{ id: 'app', version: '1.0.0', architecture: architecture, name: 'App', license: 'MIT', kind: 'linux',
		runtime: 'runtime', entrypoint: 'bin/runner', arguments: ['@APP@/app', 'literal {\"sequence\":0}'],
		permissions: ['files'], associations: ['text/plain'], dependencies: [Dependency{ id: 'runtime', minimum: '1.0.0', before: '2.0.0' }],
		files: [Payload{ path: 'app', sha256: 'b'.repeat(64), bytes: 1 }] }
	return State{ generation: 2, previous: 1, architecture: architecture, requested: ['app'], packages: [
		Installed{ package: app, repository: 'publisher', public_key: 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a', sequence: 1 },
		Installed{ package: runtime, repository: 'publisher', public_key: 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a', sequence: 1 }] }
}

fn state_validation_work(label string) !string {
	path := os.temp_dir() + '/vinix-state-' + label + '-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(path + '/generations')!
	os.mkdir(path + '/objects')!
	return path
}

fn state_validation_refusal(text string, architecture string) {
	if state := decode_persistent_state(text, architecture) {
		close_decoded_state(state)
		assert false, text
	}
}

fn test_generation_numbers_are_canonical_positive_u64_without_overflow_or_aliases() {
	assert generation_number('1')! == 1
	assert generation_number('18446744073709551615')! == ~u64(0)
	for name in ['', '0', '00', '01', '+1', '-1', '1.0', '1/2', ' 1', '1 ', '١',
		'18446744073709551616', '18446744073709551618', '999999999999999999999'] {
		if _ := generation_number(name) { assert false, name }
	}
	assert numeric_generation_name('0001') && !numeric_generation_name('1x') && !numeric_generation_name('')
}

fn test_persistent_state_requires_unambiguous_envelopes_and_typed_nested_metadata() {
	for architecture in ['aarch64', 'x86_64'] {
		original := state_validation_fixture(architecture)
		text := json2.encode(original)
		state := decode_persistent_state(text, architecture)!
		assert state == original
		close_decoded_state(state)
		for invalid in [
			text.replace('"format":1,', ''), text.replace('"previous":1,', ''),
			text.replace('"requested":["app"],', ''), text.replace('"generation":2,', ''),
			text.replace('"format":1', '"format":1,"format":1'),
			text.replace('"generation":2', '"generation":2,"generat\\u0069on":2'),
			text.replace('"format":1', '"format":1,"future":{}'),
			text.replace('"repository":"publisher"', '"repository":"publisher","repository":"publisher"'),
			text.replace('"sequence":1', '"sequence":1,"sequenc\\u0065":1'),
			text.replace('"kind":"linux"', '"kind":"linux","host_runtime":true'),
			text.replace('"minimum":"1.0.0"', '"minimum":"1.0.0","minimun":"1.0.0"'),
			text.replace('"bytes":1', '"bytes":1,"bytes":1'),
			text.replace('"generation":2', '"generation":"2"'),
			text.replace('"generation":2', '"generation":18446744073709551616'),
			text.replace('"sequence":1', '"sequence":-1'),
			text.replace('"executable":true', '"executable":"true"'),
			text.replace('"sequence":1', '"sequence":null'),
		] { state_validation_refusal(invalid, architecture) }
		// Escaped spelling is valid when it is unique; quoted values are not keys.
		escaped := decode_persistent_state(text.replace('"generation":2', '"generat\\u0069on":2'), architecture)!
		close_decoded_state(escaped)
	}
}

fn test_persistent_state_rechecks_roots_history_architecture_and_runtime_closure() {
	for architecture in ['aarch64', 'x86_64'] {
		state := state_validation_fixture(architecture)
		app := state.packages[0]
		runtime := state.packages[1]
		config := Config{ architecture: architecture, repositories: [Repository{
			id: 'publisher', url: 'file:///fixture', public_key: app.public_key }] }
		launch := launch_plan(config, '/var/lib/vinix-packages', state, 'app', '/home/user/app', 1000, 1000, [])!
		assert '/var/lib/vinix-packages/generations/2/apps/runtime/bin/runner' in launch.arguments
		mut invalid := [State{ ...state, generation: 0 }, State{ ...state, previous: 2 }, State{ ...state, previous: 3 },
			State{ ...state, format: 2 }, State{ ...state, requested: ['app', 'app'] },
			State{ ...state, requested: ['missing'] }, State{ ...state, requested: [] },
			State{ ...state, packages: [app] }, State{ ...state, packages: [app, runtime, runtime] }]
		for permissions in [['files', 'files'], ['audio', 'display', 'files', 'network', 'process', 'files']] {
			invalid << State{ ...state, packages: [Installed{ ...app, package: Package{ ...app.package, permissions: permissions } }, runtime] }
		}
		for broken in [
			Package{ ...runtime.package, permissions: ['files', 'files'] },
			Package{ ...runtime.package, kind: 'data', architecture: 'all' },
			Package{ ...runtime.package, files: [Payload{ ...runtime.package.files[0], executable: false }] },
			Package{ ...runtime.package, files: [Payload{ ...runtime.package.files[0], path: 'bin/other' }] },
			Package{ ...runtime.package, version: '2.0.0' },
			Package{ ...runtime.package, architecture: if architecture == 'aarch64' { 'x86_64' } else { 'aarch64' } },
		] { invalid << State{ ...state, packages: [app, Installed{ ...runtime, package: broken }] } }
		for broken in [Installed{ ...runtime, sequence: 0 }, Installed{ ...runtime, public_key: 'invalid' }, Installed{ ...runtime, repository: 'Publisher' }] {
			invalid << State{ ...state, packages: [app, broken] }
		}
		for broken in invalid {
			state_validation_refusal(json2.encode(broken), architecture)
			if _ := launch_plan(config, '/var/lib/vinix-packages', broken, 'app', '/home/user/app', 1000, 1000, []) {
				assert false
			}
		}
		cycle := State{ ...state, packages: [app, Installed{ ...runtime,
			package: Package{ ...runtime.package, dependencies: [Dependency{ id: 'app' }] } }] }
		accepted := decode_persistent_state(json2.encode(cycle), architecture)!
		close_decoded_state(accepted)
		for explicit in [State{ ...state, requested: ['app', 'runtime'] },
			State{ ...state, requested: ['runtime'], packages: [runtime] },
			State{ ...state, requested: ['runtime'], packages: [Installed{ ...runtime,
				package: Package{ ...runtime.package, architecture: 'all', kind: 'data' } }] }] {
			allowed := decode_persistent_state(json2.encode(explicit), architecture)!
			close_decoded_state(allowed)
		}
		removed := decode_persistent_state(json2.encode(State{ ...state, requested: [], packages: [] }), architecture)!
		close_decoded_state(removed)
	}
}

fn state_validation_write(directory string, state State) ! {
	path := directory + '/generations/' + state.generation.str()
	os.mkdir_all(path)!
	os.write_file(path + '/state.json', json2.encode(state))!
	os.write_file(path + '/lease', '')!
}

fn test_read_state_refuses_aliased_pointers_symlink_generations_and_identity_mismatch() {
	work := state_validation_work('pointer')!
	defer { os.rmdir_all(work) or {} }
	state := state_validation_fixture('aarch64')
	state_validation_write(work, state)!
	for target in ['generations/02', 'generations/0', 'generations/18446744073709551618', 'generations/2/extra', '/generations/2', 'other/2'] {
		os.symlink(target, work + '/current')!
		if read := read_state(work, 'aarch64') { close_decoded_state(read); assert false, target }
		os.rm(work + '/current')!
	}
	os.rename(work + '/generations/2', work + '/saved')!
	os.symlink(work + '/saved', work + '/generations/2')!
	os.symlink('generations/2', work + '/current')!
	if read := read_state(work, 'aarch64') { close_decoded_state(read); assert false }
	os.rm(work + '/generations/2')!
	os.rename(work + '/saved', work + '/generations/2')!
	os.write_file(work + '/generations/2/state.json', json2.encode(State{ ...state, generation: 3 }))!
	if read := read_state(work, 'aarch64') { close_decoded_state(read); assert false }
	state_validation_write(work, state)!
	accepted := read_state(work, 'aarch64')!
	close_decoded_state(accepted)
}

fn test_collection_admits_retained_states_and_all_names_leases_before_removing_anything() {
	work := state_validation_work('collection')!
	defer { os.rmdir_all(work) or {} }
	current := state_validation_fixture('aarch64')
	previous := State{ ...current, generation: 1, previous: 0 }
	state_validation_write(work, current)!
	state_validation_write(work, previous)!
	os.symlink('generations/2', work + '/current')!
	for name in ['3', '4'] { os.mkdir(work + '/generations/' + name)!; os.write_file(work + '/generations/' + name + '/lease', '')! }
	lease := C.open((work + '/generations/4/lease').str, C.O_RDONLY | C.O_CLOEXEC)
	assert lease >= 0 && C.flock(lease, C.LOCK_SH) == 0
	defer { C.close(lease) }
	for name in ['a'.repeat(64), 'b'.repeat(64), 'd'.repeat(64), 'e'.repeat(64) + '.part'] { os.write_file(work + '/objects/' + name, name)! }
	config := Config{ architecture: 'aarch64' }
	old_text := json2.encode(previous)
	for text in ['{broken', json2.encode(State{ ...previous, generation: 2 }),
		json2.encode(State{ ...previous, packages: [Installed{ ...previous.packages[0],
			package: Package{ ...previous.packages[0].package, permissions: ['files', 'files'] } }, previous.packages[1]] }),
		json2.encode(State{ ...previous, packages: [previous.packages[0], Installed{ ...previous.packages[1],
			package: Package{ ...previous.packages[1].package, kind: 'data', architecture: 'all' } }] })] {
		os.write_file(work + '/generations/1/state.json', text)!
		if _ := collect(config, work) { assert false }
		if _ := rollback(config, work) { assert false }
		assert os.is_dir(work + '/generations/3') && os.ls(work + '/objects')!.len == 4
		assert os.readlink(work + '/current')! == 'generations/2'
	}
	os.write_file(work + '/generations/1/state.json', old_text)!
	for name in ['03', '0', '18446744073709551616', '5'] {
		os.mkdir(work + '/generations/' + name)!
		if _ := collect(config, work) { assert false }
		assert os.is_dir(work + '/generations/3') && os.ls(work + '/objects')!.len == 4
		os.rmdir(work + '/generations/' + name)!
	}
	os.symlink(work + '/generations/3', work + '/generations/5')!
	if _ := collect(config, work) { assert false }
	assert os.is_dir(work + '/generations/3') && os.ls(work + '/objects')!.len == 4
	os.rm(work + '/generations/5')!
	os.mkdir(work + '/generations/5')!
	os.mkdir(work + '/generations/5/lease')!
	if _ := collect(config, work) { assert false }
	assert os.is_dir(work + '/generations/3') && os.ls(work + '/objects')!.len == 4
	os.rmdir(work + '/generations/5/lease')!
	assert C.mkfifo((work + '/generations/5/lease').str, 0o600) == 0
	if _ := collect(config, work) { assert false }
	assert os.is_dir(work + '/generations/3') && os.ls(work + '/objects')!.len == 4
	os.rm(work + '/generations/5/lease')!
	os.rmdir(work + '/generations/5')!
	collect(config, work)!
	assert !os.exists(work + '/generations/3') && os.is_dir(work + '/generations/4')
	assert os.ls(work + '/objects')!.sorted() == ['a'.repeat(64), 'b'.repeat(64)]
	assert os.readlink(work + '/current')! == 'generations/2'
	assert C.flock(lease, C.LOCK_UN) == 0
	collect(config, work)!
	assert !os.exists(work + '/generations/4')
}

fn test_generation_allocation_refuses_bad_names_before_abandoned_stage_cleanup() {
	work := state_validation_work('allocation')!
	defer { os.rmdir_all(work) or {} }
	current := state_validation_fixture('aarch64')
	state_validation_write(work, current)!
	os.mkdir(work + '/generations/.stage-sentinel')!
	for name in ['02', '18446744073709551616', '18446744073709551615'] {
		os.mkdir(work + '/generations/' + name)!
		if _ := activate_plan_locked(Config{ architecture: 'aarch64' }, work, current, Plan{}, 'remove', TransactionOptions{}) { assert false }
		assert os.is_dir(work + '/generations/.stage-sentinel')
		assert os.ls(work + '/objects')!.len == 0
		os.rmdir(work + '/generations/' + name)!
	}
	assert next_generation(work)! == 3
}

fn test_collection_rechecks_directory_lease_identity_and_late_shared_locks() {
	work := state_validation_work('collection-recheck')!
	defer { os.rmdir_all(work) or {} }
	path := work + '/generations/3'
	os.mkdir(path)!
	os.write_file(path + '/lease', '')!
	os.write_file(path + '/payload', 'protected')!
	guard := acquire(work)!
	defer { guard.release() }
	targets := collection_targets(work, State{ generation: 2, previous: 1 })!
	defer { close_collection_targets(targets) }
	assert targets.len == 1
	// An already admitted holder can change its lock state after preflight.
	lease := C.open((path + '/lease').str, C.O_RDONLY | C.O_CLOEXEC)
	assert lease >= 0 && C.flock(lease, C.LOCK_SH) == 0
	remove_collection_target(targets[0])!
	assert os.read_file(path + '/payload')! == 'protected'
	assert C.flock(lease, C.LOCK_UN) == 0
	C.close(lease)
	// Keep old inodes linked so their numbers cannot be immediately reused.
	os.rename(path + '/lease', path + '/old-lease')!
	os.write_file(path + '/lease', '')!
	if _ := remove_collection_target(targets[0]) { assert false }
	assert os.read_file(path + '/payload')! == 'protected'
	os.rm(path + '/lease')!
	os.rename(path + '/old-lease', path + '/lease')!
	os.rename(path, work + '/saved-generation')!
	os.mkdir(path)!
	os.write_file(path + '/lease', '')!
	os.write_file(path + '/replacement', 'leave intact')!
	if _ := remove_collection_target(targets[0]) { assert false }
	assert os.read_file(path + '/replacement')! == 'leave intact'
	assert os.read_file(work + '/saved-generation/payload')! == 'protected'
	os.rmdir_all(path)!
	os.symlink(work + '/saved-generation', path)!
	if _ := remove_collection_target(targets[0]) { assert false }
	assert os.read_file(work + '/saved-generation/payload')! == 'protected'
	os.rm(path)!
	os.rename(work + '/saved-generation', path)!
	remove_collection_target(targets[0])!
	assert !os.exists(path)
}
