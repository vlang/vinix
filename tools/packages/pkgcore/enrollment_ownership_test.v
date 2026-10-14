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

fn enrollment_ownership_fixture() !(string, Repository) {
	root := os.real_path(os.temp_dir()) + '/vinix-enrollment-owned-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(root + '/repo')!; os.mkdir_all(root + '/work')!
	private := signing.new_key_from_seed([]u8{len: 32, init: 7})
	return root, Repository{ id: 'fixture', url: 'file://' + root + '/repo', public_key: private.public_key().hex() }
}

fn write_owned_enrollment_index(root string, id string, sequence u64, expires i64) !string {
	private := signing.new_key_from_seed([]u8{len: 32, init: 7})
	text := canonical_index(Index{ repository: id, sequence: sequence, expires: expires })!
	bytes := text.bytes()
	signed := signing.sign(private, bytes)!
	signature := signed.hex()
	defer { unsafe { bytes.free(); signed.free(); signature.free() } }
	os.write_file(root + '/repo/index.json', text)!
	os.write_file(root + '/repo/index.sig', signature)!
	return text
}

fn decoded_enrollment_configuration(repository Repository) !Config {
	text := json2.encode(Config{ architecture: 'aarch64', repositories: [repository], launch_user: 'alex',
		policy: Policy{ offline: true, allowed: ['app'], permissions: ['files'], licenses: ['Vendor-EULA'],
			pins: [Dependency{ id: 'app', minimum: '1.0.0' }] } })
	defer { unsafe { text.free() } }
	return decode_configuration(text)
}

fn test_enrollment_snapshot_transfers_independent_owned_text_and_index_fields() {
	root, repository := enrollment_ownership_fixture()!; defer { os.rmdir_all(root) or {} }
	text := write_owned_enrollment_index(root, repository.id, 7, 2000000000)!
	index_path := root + '/repo/index.json'; signature_path := root + '/repo/index.sig'
	snapshot, index := read_enrollment_snapshot(repository, index_path, signature_path)!
	assert snapshot.text == text && snapshot.repository == repository
	os.rm(index_path)!; os.rm(signature_path)!
	unsafe { snapshot.text.free(); snapshot.signature.free() }
	// The decoded envelope must remain usable after retiring the signed input.
	assert index.repository == repository.id && index.sequence == 7 && index.expires == 2000000000
	close_decoded_index(index)
	assert repository.id == 'fixture' && repository.public_key.len == 64
	println('ENROLLMENT OWNERSHIP admitted snapshot text and decoded index have independent lifetimes; publisher identity remains borrowed PASS')
}

fn test_large_rejected_enrollment_and_signature_read_failures_release_owned_inputs() {
	root, repository := enrollment_ownership_fixture()!; defer { os.rmdir_all(root) or {} }
	index_path := root + '/repo/index.json'; signature_path := root + '/repo/index.sig'
	text := ' '.repeat(2 * 1024 * 1024 - 2) + '{}'
	os.write_file(index_path, text)!
	for kind in ['signature', 'hex', 'missing', 'directory', 'alias', 'oversized'] {
		if os.is_dir(signature_path) && !os.is_link(signature_path) { os.rmdir(signature_path)! }
		else if os.exists(signature_path) || os.is_link(signature_path) { os.rm(signature_path)! }
		match kind {
			'signature' { os.write_file(signature_path, '00'.repeat(64))! }
			'hex' { os.write_file(signature_path, '!')! }
			'directory' { os.mkdir(signature_path)! }
			'alias' { os.symlink(index_path, signature_path)! }
			'oversized' { os.write_file(signature_path, '0'.repeat(max_metadata + 1))! }
			else {}
		}
		for _ in 0 .. 16 {
			$if track_heap ? { C.vinix_heap_begin() }
			if snapshot, index := read_enrollment_snapshot(repository, index_path, signature_path) {
				close_decoded_index(index); unsafe { snapshot.text.free(); snapshot.signature.free() }; assert false
			} else {
				message := err.msg()
				assert message.contains(match kind { 'signature' { 'signature verification failed' } 'hex' { 'invalid hex char' } else { 'bounded regular file' } })
				unsafe { message.free(); err.free() }
			}
			$if track_heap ? { kept := C.vinix_heap_end(); count := C.vinix_heap_count(); assert kept == 0 && count == 0, '${kind}: ${kept} bytes / ${count} allocations retained' }
		}
		assert os.read_file(index_path)! == text && repository.id == 'fixture'
	}
	println('ENROLLMENT OWNERSHIP 16 repeats of six large signature/authentication/read failures release all reader and input scratch PASS')
}

fn test_authenticated_metadata_refusals_remain_errors_and_allow_a_restored_retry() {
	root, repository := enrollment_ownership_fixture()!; defer { os.rmdir_all(root) or {} }
	config := Config{ architecture: 'aarch64', policy: Policy{ offline: true } }
	for kind in ['expired', 'identity', 'sequence'] {
		write_owned_enrollment_index(root, if kind == 'identity' { 'other' } else { repository.id },
			if kind == 'sequence' { u64(0) } else { u64(7) }, if kind == 'expired' { i64(1) } else { i64(2000000000) })!
		if snapshot, index := enrollment_snapshot(config, repository, true, root + '/work') {
			close_decoded_index(index); unsafe { snapshot.text.free(); snapshot.signature.free() }; assert false
		} else { assert err.msg().contains('expired, incompatible or misidentified') }
	}
	text := write_owned_enrollment_index(root, repository.id, 8, 2000000000)!
	snapshot, index := enrollment_snapshot(config, repository, true, root + '/work')!
	assert snapshot.text == text && index.sequence == 8
	close_decoded_index(index); unsafe { snapshot.text.free(); snapshot.signature.free() }
	println('ENROLLMENT OWNERSHIP expired, misidentified and zero-sequence signed metadata refuse; restored offline acquisition retries normally PASS')
}

fn test_proposed_configuration_owns_new_identity_and_borrows_retained_fields() {
	root, repository := enrollment_ownership_fixture()!; defer { os.rmdir_all(root) or {} }
	current := decoded_enrollment_configuration(repository)!
	defer { close_decoded_configuration(current) }
	proposed := Repository{ ...repository, id: 'new' }
	for input in [proposed, Repository{ ...proposed, public_key: 'bad' }, Repository{ ...proposed, public_key: '01' + '00'.repeat(31) }] {
		for iteration in 0 .. 17 {
			$if track_heap ? { if iteration > 0 { C.vinix_heap_begin() } }
			if next := enrollment_configuration(current, input) {
				assert input == proposed && next.repositories.len == 2 && next.repositories[0].id == 'fixture'
				close_enrollment_configuration(next, input.id)
			} else {
				message := err.msg(); assert input != proposed
				unsafe { message.free(); err.free() }
			}
			$if track_heap ? {
				if iteration > 0 {
					kept := C.vinix_heap_end(); count := C.vinix_heap_count()
					assert kept == 0 && count == 0, '${kept} bytes / ${count} allocations retained'
				}
			}
		}
		assert current.repositories.len == 1 && current.repositories[0] == repository && current.policy.permissions == ['files']
	}
	input := Repository{ id: proposed.id.clone(), url: proposed.url.clone(), public_key: proposed.public_key.clone() }
	next := enrollment_configuration(current, input)!
	unsafe { input.id.free(); input.url.free(); input.public_key.free() }
	assert next.repositories[1] == proposed && next.repositories[0] == current.repositories[0]
	close_enrollment_configuration(next, proposed.id)
	println('ENROLLMENT OWNERSHIP proposed configuration growth and syntax/curve refusal retire array scratch and preserve borrowed source fields PASS')
}

fn test_repository_review_results_survive_source_retirement_and_rejected_builds_release_fields() {
	root, repository := enrollment_ownership_fixture()!; defer { os.rmdir_all(root) or {} }
	current := decoded_enrollment_configuration(repository)!
	index := Index{ repository: repository.id, sequence: 7, expires: 2000000000 }
	history := TrustHistory{}
	for operation in ['enroll', 'unknown'] {
		for iteration in 0 .. 17 {
			$if track_heap ? { if iteration > 0 { C.vinix_heap_begin() } }
			if operation == 'enroll' {
				mut owned := repository_review(current, history, operation, repository, 'authenticated index', index)!
				owned.close()
			} else {
				if value := repository_review(current, history, operation, repository, 'authenticated index', index) { assert false, value.operation }
				else {
					message := err.msg(); assert operation == 'unknown' && message.contains('unsupported repository review')
					unsafe { message.free(); err.free() }
				}
			}
			$if track_heap ? {
				if iteration > 0 {
					kept := C.vinix_heap_end(); count := C.vinix_heap_count()
					assert kept == 0 && count == 0, '${kept} bytes / ${count} allocations retained'
				}
			}
		}
	}
	mut review := repository_review(current, history, 'enroll', current.repositories[0], 'authenticated index', index)!
	close_decoded_configuration(current)
	assert review.id == repository.id && review.url == repository.url && review.public_key == repository.public_key
	assert review.previous_url == review.url && review.previous_public_key == review.public_key && review.sequence == 7
	review.validate()!; review.close()
	println('ENROLLMENT OWNERSHIP accepted reviews own independent fields; rejected review construction releases all clones and fingerprints PASS')
}

fn test_public_repository_review_preserves_trust_state_and_remains_usable_after_private_cleanup() {
	root, repository := enrollment_ownership_fixture()!; defer { os.rmdir_all(root) or {} }
	os.mkdir_all(root + '/etc/vinix-packages')!
	path := root + '/etc/vinix-packages/config.json'
	configuration := json2.encode(Config{ architecture: 'aarch64', launch_user: 'alex', policy: Policy{ offline: true, permissions: ['files'] } })
	os.write_file(path, configuration)!; os.chmod(path, 0o644)!
	write_owned_enrollment_index(root, repository.id, 7, 2000000000)!
	os.write_file(root + '/repo/index.sig', '00'.repeat(64))!
	for _ in 0 .. 3 {
		if value := review_repository(root, 'enroll', repository, true) { mut owned := value; owned.close(); assert false }
		assert os.read_file(path)! == configuration && !os.exists(state_directory(root))
	}
	write_owned_enrollment_index(root, repository.id, 7, 2000000000)!
	mut review := review_repository(root, 'enroll', repository, true)!
	assert review.id == repository.id && review.url == repository.url && review.index_sha256.len == 64
	assert review.previous_public_key == '' && review.sequence == 7 && !os.exists(state_directory(root))
	enroll_repository_reviewed(root, repository, true, review.fingerprint)!
	review.close()
	before := os.read_file(state_directory(root) + '/trust-history.json')!
	mut revocation := review_repository(root, 'revoke', Repository{ id: repository.id }, true)!
	assert revocation.url == repository.url && revocation.previous_url == revocation.url && revocation.previous_public_key == repository.public_key
	revoke_repository_reviewed(root, repository.id, revocation.fingerprint)!
	revocation.close()
	assert load_config(root)!.repositories.len == 0 && os.read_file(state_directory(root) + '/trust-history.json')! == before
	println('ENROLLMENT OWNERSHIP public failure/review/apply/revocation preserve read-only trust state, independent review fields and retained replay history PASS')
}
