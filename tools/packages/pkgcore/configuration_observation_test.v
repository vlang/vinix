// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import tools.packages.pkgprotocol

fn C.mkfifo(&char, u32) int

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn configuration_observation_fixture() !(string, Service) {
	root := os.temp_dir() + '/vinix-config-observation-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(root + '/etc/vinix-packages')!
	config := Config{ architecture: 'aarch64', launch_user: 'alex', repositories: [Repository{ id: 'publisher', url: 'file:///offline/repository', public_key: '01' + '00'.repeat(31) }],
		policy: Policy{ offline: true, allowed: ['utility', 'app'], pins: [Dependency{ id: 'app', minimum: '1.0.0', before: '2.0.0' }],
			permissions: ['files'], licenses: ['Vendor é🚀'], allow_firmware: true, reserve_bytes: 7 } }
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(config))!
	return root, Service{ root: root }
}

fn retire_configuration_observation(mut document RepositoryConfiguration) {
	document.close(); document.close()
	assert document.architecture == '' && document.repositories.len == 0
}

fn test_configuration_observations_retire_results_and_reader_scratch() {
	$if track_heap ? {
		root, service := configuration_observation_fixture()!; defer { os.rmdir_all(root) or {} }
		C.vinix_heap_begin()
		for _ in 0 .. 1000 { mut document := repository_configuration(root)!; retire_configuration_observation(mut document) }
		repository_bytes := C.vinix_heap_end()
		C.vinix_heap_begin()
		for _ in 0 .. 1000 { mut document := service.policy()!; document.close(); document.close() }
		policy_bytes := C.vinix_heap_end()
		println('CONFIGURATION OBSERVATION 1000 repository reads/retirements retained ${repository_bytes} bytes; 1000 policy reads/retirements retained ${policy_bytes} bytes')
		assert repository_bytes == 0 && policy_bytes == 0
	}
}

fn test_configuration_observations_own_fields_preserve_protocols_and_stored_policy() {
	for architecture in ['aarch64', 'x86_64']! {
		root, service := configuration_observation_fixture()!; defer { os.rmdir_all(root) or {} }
		path := root + '/etc/vinix-packages/config.json'
		text := os.read_file(path)!.replace('aarch64', architecture)
		os.write_file(path, text)!
		mut first := repository_configuration(root)!; mut second := repository_configuration(root)!
		mut before := service.policy()!; mut after := service.policy()!
		assert first == second && first.architecture == architecture && first.scope == 'configuration'
		assert first.repositories.data != second.repositories.data && first.architecture.str != second.architecture.str
		assert before == after && before.policy.allowed == ['app', 'utility']
		assert before.policy.allowed.data != after.policy.allowed.data
		mut repository_wire := pkgprotocol.decode_repository_configuration(json2.encode(first))!
		assert repository_wire.repositories[0].id == 'publisher' && json2.encode(repository_wire) == json2.encode(first); repository_wire.close()
		mut policy_wire := pkgprotocol.decode_policy_document(json2.encode(before))!
		assert policy_wire.policy.licenses == ['Vendor é🚀'] && json2.encode(policy_wire) == json2.encode(before); policy_wire.close()
		assert os.read_file(path)! == text && !os.exists(state_directory(root))
		retire_configuration_observation(mut first); before.close(); before.close()
		os.write_file(path, '{replaced configuration')!
		assert second.repositories[0].url == 'file:///offline/repository' && second.repositories[0].public_key == '01' + '00'.repeat(31)
		assert after.architecture == architecture && after.policy.pins[0].minimum == '1.0.0' && after.policy.licenses == ['Vendor é🚀']
		retire_configuration_observation(mut second); after.close(); after.close()
		stored := text.replace('"offline":true', '"offline":false'); os.write_file(path, stored)!
		mut policy := (Service{ root: root, offline: true }).policy()!
		assert !policy.policy.offline && os.read_file(path)! == stored; policy.close()
	}
	println('CONFIGURATION OBSERVATION both architectures, independent repository/policy fields, canonical policy order, unchanged wire bytes and stored offline flag PASS')
}

fn test_configuration_observations_bound_growth_and_retire_legacy_defaults() {
	root, service := configuration_observation_fixture()!; defer { os.rmdir_all(root) or {} }
	path := root + '/etc/vinix-packages/config.json'
	defaults := Policy{}; expected_default := canonical_policy(defaults)!
	defer { close_owned_policy(defaults); close_owned_policy(expected_default) }
	for count in [0, 64, 4096]! {
		mut repositories := []Repository{cap: count}; mut pins := []Dependency{cap: count}; mut allowed := []string{cap: count}
		for index in 0 .. count {
			id := 'app-' + index.str()
			repositories << Repository{ id: id, url: 'file:///offline/repository', public_key: 'a'.repeat(64) }
			pins << Dependency{ id: id, minimum: '1.0.0', before: '2.0.0' }; allowed << id
		}
		text := if count == 0 { '{"architecture":"aarch64"}' } else {
			json2.encode(Config{ architecture: 'aarch64', repositories: repositories, policy: Policy{ pins: pins, allowed: allowed } })
		}
		os.write_file(path, text)!
		// The maximum valid result legitimately exceeds the tracker's live-record
		// table while both source configuration and canonical policy coexist.
		tracked := count != 4096
		$if track_heap ? { if tracked { C.vinix_heap_begin() } }
		for _ in 0 .. if tracked { 1000 } else { 1 } {
			mut configuration := repository_configuration(root)!; assert configuration.repositories.len == count
			retire_configuration_observation(mut configuration)
			mut policy := service.policy()!; assert policy.policy.pins.len == count
			if count == 0 { assert policy.policy == expected_default }
			else { assert policy.policy.allowed[0] == 'app-0' && policy.policy.pins[0].id == 'app-0' }
			policy.close(); policy.close()
		}
		$if track_heap ? { if tracked { kept := C.vinix_heap_end(); assert kept == 0, 'legacy/growing reader scratch retained ' + kept.str() } }
		assert os.read_file(path)! == text && !os.exists(state_directory(root))
	}
	println('CONFIGURATION OBSERVATION 1000 legacy/default and growing 64-record cycles retire scratch; full 4096 repository/pin observations preserve source configuration PASS')
}

fn configuration_observation_refusal(root string, service Service, expected string) {
	if mut document := repository_configuration(root) { document.close(); assert false }
	else { message := err.msg(); assert message != '' && message.contains(expected), message; unsafe { message.free(); err.free() } }
	if mut document := service.policy() { document.close(); assert false }
	else { message := err.msg(); assert message != '' && message.contains(expected), message; unsafe { message.free(); err.free() } }
}

fn test_configuration_observations_ignore_maintenance_metadata_and_retire_refusal_scratch() {
	root, service := configuration_observation_fixture()!; defer { os.rmdir_all(root) or {} }
	path := root + '/etc/vinix-packages/config.json'; text := os.read_file(path)!
	directory := state_directory(root); guard := acquire(directory)!; guard.release()
	assert C.mkfifo((directory + '/catalog.json').str, 0o600) == 0
	assert C.mkfifo((directory + '/trust-history.json').str, 0o600) == 0
	mut configuration := repository_configuration(root)!; retire_configuration_observation(mut configuration)
	mut policy := service.policy()!; assert policy.policy.allow_firmware; policy.close()
	for failure in ['schema', 'missing', 'alias', 'fifo', 'lock', 'busy']! {
		mut writer := Lock{ fd: -1 }
		match failure {
			'schema' { os.write_file(path, text.replace('"permissions":', '"permissons":'))! }
			'missing' { os.rm(path)! }
			'alias' { os.rm(path)!; os.symlink(root + '/missing', path)! }
			'fifo' { os.rm(path)!; assert C.mkfifo(path.str, 0o600) == 0 }
			'lock' { os.rm(directory + '/lock')!; os.symlink(root + '/missing-lock', directory + '/lock')! }
			'busy' { writer = acquire(directory)!; os.write_file(path, '{must not be read')! }
			else {}
		}
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. 1000 { configuration_observation_refusal(root, service, if failure == 'busy' { 'another package transaction' } else { '' }) }
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, failure + ' retained ' + kept.str() }
		if failure == 'busy' { writer.release() }
		if failure in ['alias', 'fifo']! { os.rm(path)! }
		if failure == 'lock' { os.rm(directory + '/lock')!; os.write_file(directory + '/lock', '')!; os.chmod(directory + '/lock', 0o644)! }
		os.write_file(path, text)!
		mut restored := repository_configuration(root)!; retire_configuration_observation(mut restored)
		mut restored_policy := service.policy()!; restored_policy.close()
	}
	assert os.read_file(path)! == text && !os.exists(directory + '/current')
	assert os.ls(directory + '/objects')!.len == 0 && os.ls(directory + '/generations')!.len == 0
	assert os.lstat(directory + '/catalog.json')!.mode & 0o170000 == 0o010000
	assert os.lstat(directory + '/trust-history.json')!.mode & 0o170000 == 0o010000
	println('CONFIGURATION OBSERVATION maintenance FIFOs remain unopened; 1000 schema/missing/alias/FIFO/lock/busy refusal cycles retire scratch and permit restored reads PASS')
}
