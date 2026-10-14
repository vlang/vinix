// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import crypto.sha256
import os
import time
import tools.packages.signing

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

fn history_ownership_fixture() !(string, []Snapshot) {
	directory := os.temp_dir() + '/vinix-history-ownership-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(directory)!
	private := signing.new_key_from_seed([]u8{len: 32, init: 7})
	repository := Repository{ id: 'trusted', url: 'file:///unused-history-source', public_key: private.public_key().hex() }
	p := Package{ id: 'app', name: 'Data', version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT',
		description: 'd'.repeat(2048), arguments: ['x'.repeat(2048)], files: [Payload{ path: 'asset', sha256: 'a'.repeat(64) }] }
	text := canonical_index(Index{ repository: repository.id, sequence: 7, expires: 1, packages: [p] })!
	signature := signing.sign(private, text.bytes())!.hex()
	// Independently decoded input strings make borrowed-result mistakes visible
	// to ASan when the snapshot is retired before the resulting replay history.
	return directory, decode_snapshots(json2.encode([Snapshot{ repository: repository, text: text, signature: signature }]))!
}

fn test_migrated_history_owns_its_fields_after_input_snapshots_retire() {
	directory, snapshots := history_ownership_fixture()!; defer { os.rmdir_all(directory) or {} }
	digest := index_digest(snapshots[0].text)
	history := history_with_snapshots(Config{ architecture: 'aarch64' }, directory, snapshots)!
	close_decoded_snapshots(snapshots)
	assert history.repositories.len == 1 && history.repositories[0].id == 'trusted'
	assert history.repositories[0].public_key.len == 64 && history.repositories[0].sequence == 7
	assert history.repositories[0].index_sha256 == digest
	save_history(directory, history)!
	reloaded := read_history(directory)!
	assert reloaded == history
	close_decoded_history(reloaded); close_decoded_history(history)
	println('HISTORY OWNERSHIP migrated expired snapshots produce independent replay records and survive input retirement PASS')
}

fn test_repeated_history_migration_and_retirement_bound_reader_scratch() {
	directory, snapshots := history_ownership_fixture()!; defer { os.rmdir_all(directory) or {} }
	defer { close_decoded_snapshots(snapshots) }
	config := Config{ architecture: 'aarch64' }
	warm := history_with_snapshots(config, directory, snapshots)!; close_decoded_history(warm)
	mut maximum := u64(0); mut maximum_count := u32(0)
	for _ in 0 .. 64 {
		$if track_heap ? { C.vinix_heap_begin() }
		history := history_with_snapshots(config, directory, snapshots)!
		close_decoded_history(history)
		$if track_heap ? {
			kept := C.vinix_heap_end(); count := C.vinix_heap_count()
			assert kept <= 512 && count <= 5, '${kept} bytes / ${count} allocations retained'
			if kept > maximum { maximum = kept }; if count > maximum_count { maximum_count = count }
		}
	}
	assert snapshots[0].repository.id == 'trusted' && snapshots[0].text.contains('"sequence":7')
	println('HISTORY OWNERSHIP 64 authenticated migrations/retirements preserve source snapshots within reader budget: ${maximum} bytes / ${maximum_count} allocations PASS')
}

fn test_remembering_an_index_preserves_source_records_and_returns_independent_sorted_fields() {
	input := decode_history('{"format":1,"repositories":[{"id":"unrelated","public_key":"' + 'a'.repeat(64) + '","sequence":9,"index_sha256":"' + 'b'.repeat(64) + '"}]}', false)!
	directory, snapshots := history_ownership_fixture()!; defer { os.rmdir_all(directory) or {} }
	remembered := remember_index(input, snapshots[0].repository, Index{ sequence: 7 }, snapshots[0].text)!
	close_decoded_history(input); close_decoded_snapshots(snapshots)
	assert remembered.repositories.len == 2 && remembered.repositories[0].id == 'trusted'
	assert remembered.repositories[1].id == 'unrelated' && remembered.repositories[1].sequence == 9
	assert remembered.repositories[1].index_sha256 == 'b'.repeat(64)
	close_decoded_history(remembered)
	println('HISTORY OWNERSHIP remembered indexes detach both existing and new identity fields and preserve sorted floors PASS')
}

fn test_later_signature_and_equivocation_failures_retire_partial_history_without_publishing() {
	directory, snapshots := history_ownership_fixture()!; defer { os.rmdir_all(directory) or {} }
	defer { close_decoded_snapshots(snapshots) }
	config := Config{ architecture: 'aarch64' }
	// The second entry is deliberately the same identity: first verification
	// succeeds, while the second fails authentication or same-sequence digest.
	bad_signature := Snapshot{ ...snapshots[0], signature: '00'.repeat(64) }
	private := signing.new_key_from_seed([]u8{len: 32, init: 7})
	changed := snapshots[0].text + ' '
	bad_digest := Snapshot{ ...snapshots[0], text: changed, signature: signing.sign(private, changed.bytes())!.hex() }
	for bad in [bad_signature, bad_digest] {
		entries := [snapshots[0], bad]
		$if track_heap ? { C.vinix_heap_begin() }
		if result := history_with_snapshots(config, directory, entries) { close_decoded_history(result); assert false } else {
			message := err.msg()
			assert message.contains(if bad.signature == bad_signature.signature { 'signature verification failed' } else { 'sequence equivocation' })
			unsafe { message.free(); err.free() }
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept <= 1024 && C.vinix_heap_count() <= 10 }
		assert !os.exists(directory + '/trust-history.json')
	}
	println('HISTORY OWNERSHIP later signature/equivocation failures retire partial results without publishing history PASS')
}

fn test_retained_newer_floors_are_not_replaced_by_older_authenticated_snapshots() {
	directory, snapshots := history_ownership_fixture()!; defer { os.rmdir_all(directory) or {} }
	defer { close_decoded_snapshots(snapshots) }
	history := TrustHistory{ repositories: [RepositoryFloor{ id: snapshots[0].repository.id,
		public_key: snapshots[0].repository.public_key, sequence: 8, index_sha256: 'b'.repeat(64) }] }
	save_history(directory, history)!
	before := os.read_file(directory + '/trust-history.json')!
	config := Config{ architecture: 'aarch64' }
	for _ in 0 .. 8 {
		$if track_heap ? { C.vinix_heap_begin() }
		result := history_with_snapshots(config, directory, snapshots)!
		assert result.repositories[0].sequence == 8 && result.repositories[0].index_sha256 == history.repositories[0].index_sha256
		close_decoded_history(result)
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept <= 512 && C.vinix_heap_count() <= 5 }
	}
	assert os.read_file(directory + '/trust-history.json')! == before
	println('HISTORY OWNERSHIP newer retained floors survive authenticated older cache migration with bounded lifetimes PASS')
}

fn test_full_history_replacement_and_identity_limit_failure_release_scratch() {
	mut floors := []RepositoryFloor{}
	for i in 0 .. 4096 {
		floors << RepositoryFloor{ id: 'retained-' + i.str(), public_key: 'a'.repeat(64), sequence: 9, index_sha256: 'b'.repeat(64) }
	}
	// Decode independent fields so retiring either side detects accidental
	// ownership sharing, including all records copied during array growth.
	input := decode_history(json2.encode(TrustHistory{ repositories: floors }), false)!
	defer { close_decoded_history(input) }
	for id in ['new-identity', input.repositories[0].id] {
		repository := Repository{ id: id, public_key: input.repositories[0].public_key }
		$if track_heap ? { C.vinix_heap_begin() }
		if result := remember_index(input, repository, Index{ sequence: 10 }, 'authenticated index bytes') {
			assert id != 'new-identity' && result.repositories.len == 4096
			assert result.repositories[0].id == input.repositories[0].id && result.repositories[0].sequence == 10
			close_decoded_history(result)
		} else {
			message := err.msg(); assert id == 'new-identity' && message == 'repository trust history exceeds its supported identity limit'
			unsafe { message.free(); err.free() }
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 && C.vinix_heap_count() == 0 }
		assert input.repositories.len == 4096 && input.repositories[0].sequence == 9
	}
	println('HISTORY OWNERSHIP full 4096-identity replacement and overflow refusal release scratch without mutating source floors PASS')
}

fn test_index_digest_preserves_sha256_vectors_and_block_boundaries_without_scratch() {
	assert index_digest('') == 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
	assert index_digest('abc') == 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
	for length in [55, 56, 63, 64, 65, 127, 128, 129, 4096] {
		text := 'x'.repeat(length) + '\x00é/文件'
		expected := sha256.hexhash(text)
		$if track_heap ? { C.vinix_heap_begin() }
		actual := index_digest(text)
		assert actual == expected
		unsafe { actual.free() }
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 && C.vinix_heap_count() == 0 }
	}
	println('HISTORY OWNERSHIP SHA256 vectors, binary/Unicode bytes and block boundaries preserve replay digests with zero hashing scratch PASS')
}
