// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import tools.packages.signing

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

fn administration_request(root string, repository Repository, mode string, expected string) !Config {
	return match mode {
		'enroll' { enroll_repository(root, repository, true) }
		'replace', 'stale-enroll', 'write-enroll' { enroll_repository_reviewed(root, repository, true, expected) }
		'revoke' { revoke_repository(root, repository.id) }
		else { revoke_repository_reviewed(root, repository.id, expected) }
	}
}

fn administration_request_scope(architecture string, mode string) ! {
	root := os.real_path(os.temp_dir()) + '/vinix-trust-request-' + os.getpid().str()
	defer { os.rmdir_all(root) or {} }
	directory := state_directory(root)
	parent := root + '/etc/vinix-packages'
	path := parent + '/config.json'
	history := directory + '/trust-history.json'
	cache := directory + '/catalog.json'
	source := root + '/signed'
	os.mkdir_all(parent)!
	os.mkdir_all(source)!
	guard := acquire(directory)!
	guard.release()

	private := signing.new_key_from_seed([]u8{len: 32, init: 7})
	old_private := signing.new_key_from_seed([]u8{len: 32, init: 8})
	proposed := Repository{ id: 'target', url: 'file://' + source, public_key: private.public_key().hex() }
	retained := Repository{ id: 'retained', url: 'file://' + root + '/retained', public_key: old_private.public_key().hex() }
	original := Repository{ ...proposed, url: 'file://' + root + '/unavailable', public_key: retained.public_key }
	config := Config{ architecture: architecture, launch_user: 'alex', policy: Policy{ offline: true,
		reserve_bytes: 1234, permissions: ['files'], licenses: ['Vendor-EULA'], allowed: ['app'],
		pins: [Dependency{ id: 'app', minimum: '1.0.0', before: '3.0.0' }] },
		repositories: if mode in ['enroll', 'missing']! { [retained] } else { [retained, original] } }
	text := canonical_index(Index{ repository: proposed.id, sequence: 8, expires: time.now().unix() + 86400 })!
	signature := signing.sign(private, text.bytes())!.hex()
	os.write_file(source + '/index.json', text)!
	os.write_file(source + '/index.sig', signature)!
	save_configuration(path, config)!
	configuration := os.read_file(path)!

	enrolling := mode in ['enroll', 'replace', 'stale-enroll', 'write-enroll']!
	durable_history := if enrolling { json2.encode(TrustHistory{ repositories: [
		RepositoryFloor{ id: original.id, public_key: original.public_key, sequence: 4, index_sha256: 'a'.repeat(64) }
	] }) } else { 'intentionally damaged history' }
	expected_history := if mode in ['enroll', 'replace', 'write-enroll']! {
		prior := json2.decode[TrustHistory](durable_history)!
		floors := remember_index(prior, proposed, Index{ sequence: 8 }, text)!
		json2.encode(floors) + '\n'
	} else { durable_history }
	durable_cache := if enrolling { '[]' } else { 'intentionally damaged cache' }
	os.write_file(history, durable_history)!
	os.write_file(cache, durable_cache)!
	mut expected := ''
	if mode in ['replace', 'reviewed-revoke', 'write-enroll', 'write-revoke']! {
		mut review := review_repository(root, if enrolling { 'enroll' } else { 'revoke' }, proposed, true)!
		expected = review.fingerprint.clone()
		review.close()
	} else if mode in ['stale-enroll', 'stale-revoke']! { expected = '0'.repeat(64) }
	refusal := match mode {
		'stale-enroll', 'stale-revoke' { 'repository review is stale' }
		'missing' { 'repository is not enrolled' }
		'busy' { 'another package transaction' }
		'unsafe' { 'administrator-owned ordinary configuration' }
		'write-enroll', 'write-revoke' { 'cannot create a private package metadata temporary file' }
		else { '' }
	}
	expected_repositories := if enrolling { [retained, proposed] } else { [retained] }
	block_config_write := mode in ['write-enroll', 'write-revoke']!
	defer { if block_config_write { os.chmod(parent, 0o755) or {} } }
	mut retained_bytes := u64(0)
	mut retained_allocations := u64(0)
	for call in 0 .. 36 {
		os.write_file(path, configuration)!
		os.write_file(history, durable_history)!
		mut busy := Lock{ fd: -1 }
		if mode == 'busy' { busy = acquire(directory)! }
		if mode == 'unsafe' { os.chmod(path, 0o666)! }
		if block_config_write { os.chmod(parent, 0o555)! }
		$if track_heap ? { if call >= 4 { C.vinix_heap_begin() } }
		if mut result := administration_request(root, proposed, mode, expected) {
			assert refusal == ''
			assert result.architecture == architecture && result.launch_user == config.launch_user
			assert result.policy == config.policy && result.repositories == expected_repositories
			$if administration_request_baseline ? {
				close_decoded_configuration(result)
			} $else {
				result.close()
				result.close()
			}
		} else {
			message := err.msg()
			assert refusal != '' && message.contains(refusal), message
			unsafe { message.free(); err.free() }
		}
		$if track_heap ? {
			if call >= 4 {
				retained_bytes += C.vinix_heap_end()
				retained_allocations += C.vinix_heap_count()
			}
		}
		if busy.fd >= 0 { busy.release() }
		if block_config_write { os.chmod(parent, 0o755)! }
		if mode == 'unsafe' { os.chmod(path, 0o644)! }
		if refusal == '' {
			stored := load_config(root)!
			assert stored.repositories == expected_repositories && stored.policy == config.policy
			close_decoded_configuration(stored)
		} else {
			assert os.read_file(path)! == configuration
		}
		assert os.read_file(cache)! == durable_cache && os.read_file(history)! == expected_history
		assert !os.exists(directory + '/enrollment')
	}
	println('TRUST REQUEST ${architecture} ${mode}: ${retained_bytes} bytes / ${retained_allocations} allocations retained')
	$if !administration_request_baseline ? {
		assert retained_bytes == 0 && retained_allocations == 0, mode
	}
}

fn test_complete_repository_administration_requests_retire_owned_configuration() {
	mut scopes := 0
	for architecture in ['aarch64', 'x86_64']! {
		for mode in ['enroll', 'replace', 'revoke', 'reviewed-revoke', 'stale-enroll', 'stale-revoke',
			'missing', 'busy', 'unsafe', 'write-enroll', 'write-revoke']! {
			if os.geteuid() == 0 && mode in ['write-enroll', 'write-revoke']! { continue }
			administration_request_scope(architecture, mode)!
			scopes++
		}
	}
	println('TRUST REQUEST ${scopes} scopes across ${scopes * 32} measured calls preserve configuration, exact history and cached data PASS')
}
