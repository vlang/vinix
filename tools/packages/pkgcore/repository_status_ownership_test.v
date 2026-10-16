// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import tools.packages.pkgprotocol
import tools.packages.signing

fn C.mkfifo(&char, u32) int

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
	fn C.vinix_heap_size_at(u32) u64
}

fn test_repository_status_owns_both_architectures_and_growing_retained_documents() {
	for architecture in ['aarch64', 'x86_64']! {
		root := repository_status_fixture()!; defer { os.rmdir_all(root) or {} }
		directory := state_directory(root); guard := acquire(directory)!; guard.release()
		path := root + '/etc/vinix-packages/config.json'
		for count in [0, 64, 4096]! {
			mut repositories := []Repository{cap: count}; mut floors := []RepositoryFloor{cap: count}
			for i in 0 .. count {
				id := 'publisher-' + i.str()
				repositories << Repository{ id: id, url: 'file:///repository', public_key: 'a'.repeat(64) }
				floors << RepositoryFloor{ id: id, public_key: 'a'.repeat(64), sequence: 7, index_sha256: 'b'.repeat(64) }
			}
			configuration := json2.encode(Config{ architecture: architecture, repositories: repositories, launch_user: 'alex', policy: Policy{ licenses: ['Vendor é🚀'] } })
			history := json2.encode(TrustHistory{ repositories: floors })
			os.write_file(path, configuration)!; os.write_file(directory + '/trust-history.json', history)!
			// The combined maximum has over 16,384 live owned strings. Qualify it
			// functionally and under ASan; track empty/growing observations.
			tracked := count != 4096
			$if track_heap ? { if tracked { C.vinix_heap_begin() } }
			for _ in 0 .. if tracked { 1000 } else { 1 } {
				mut status := repository_status(root)!; assert status.repositories.len == count && status.history.len == count
				retire_repository_status(mut status)
			}
			$if track_heap ? { if tracked { kept := C.vinix_heap_end(); assert kept == 0 } }
			mut first := repository_status(root)!; mut second := repository_status(root)!
			assert first == second && first.architecture == architecture && first.architecture.str != second.architecture.str
			if count > 0 { assert first.repositories.data != second.repositories.data && first.history.data != second.history.data }
			mut wire := pkgprotocol.decode_repositories(json2.encode(second))!
			assert json2.encode(wire) == json2.encode(second); wire.close()
			assert os.read_file(path)! == configuration && os.read_file(directory + '/trust-history.json')! == history
			retire_repository_status(mut first)
			os.write_file(path, '{replaced configuration')!; os.write_file(directory + '/trust-history.json', '{replaced history')!
			if count > 0 { assert second.repositories[count - 1].id == repositories[count - 1].id && second.history[count - 1].sequence == 7 && second.history[0].index_sha256 == 'b'.repeat(64) }
			assert second.architecture == architecture; retire_repository_status(mut second)
			os.write_file(path, configuration)!; os.write_file(directory + '/trust-history.json', history)!
		}
		assert !os.exists(directory + '/current') && !os.exists(directory + '/catalog.json')
		assert os.ls(directory + '/objects')!.len == 0 && os.ls(directory + '/generations')!.len == 0
	}
	println('REPOSITORY STATUS both architectures, independent owned fields, repeated close, source replacement, exact protocol bytes and full 4096 repository/history bounds PASS')
}

fn repository_status_refusal(root string, expected string) {
	if mut status := repository_status(root) { status.close(); assert false }
	else { message := err.msg(); assert message != '' && message.contains(expected), message; unsafe { message.free(); err.free() } }
}

fn test_repository_status_preserves_authenticated_migration_and_retired_replay_floors() {
	for architecture in ['aarch64', 'x86_64']! {
		root := repository_status_fixture()!; defer { os.rmdir_all(root) or {} }
		directory := state_directory(root); guard := acquire(directory)!; guard.release()
		path := root + '/etc/vinix-packages/config.json'
		private := signing.new_key_from_seed([]u8{len: 32, init: 7})
		repository := Repository{ id: 'publisher', url: 'file:///repository', public_key: private.public_key().hex() }
		configuration := json2.encode(Config{ architecture: architecture, repositories: [repository] })
		os.write_file(path, configuration)!
		// Expiry does not erase legacy replay floors during a read-only listing.
		text := canonical_index(Index{ repository: repository.id, sequence: 7, expires: 1 })!
		snapshot := Snapshot{ repository: repository, text: text, signature: signing.sign(private, text.bytes())!.hex() }
		cache := json2.encode([snapshot]); os.write_file(directory + '/catalog.json', cache)!
		mut warm := repository_status(root)!; warm.close() // warm the existing signed-index decoder's metadata cache
		for phase in ['legacy', 'newer', 'signature', 'equivocation']! {
			history := if phase == 'legacy' { '' } else { json2.encode(TrustHistory{ repositories: [RepositoryFloor{ id: repository.id, public_key: repository.public_key,
				sequence: if phase == 'newer' { u64(10) } else { u64(7) }, index_sha256: if phase == 'signature' { index_digest(text) } else { 'a'.repeat(64) } }] }) }
			if phase != 'legacy' { os.write_file(directory + '/trust-history.json', history)! }
			current_cache := if phase == 'signature' { json2.encode([Snapshot{ ...snapshot, signature: '00'.repeat(64) }]) } else { cache }
			os.write_file(directory + '/catalog.json', current_cache)!
			$if track_heap ? { C.vinix_heap_begin() }
			for _ in 0 .. 64 {
				if phase in ['signature', 'equivocation']! { repository_status_refusal(root, if phase == 'signature' { 'signature verification failed' } else { 'sequence equivocation' }) }
				else {
					mut status := repository_status(root)!; assert status.history.len == 1 && status.history[0].sequence == if phase == 'legacy' { u64(7) } else { u64(10) }
					retire_repository_status(mut status)
				}
			}
			$if track_heap ? {
				kept := C.vinix_heap_end()
				if phase == 'signature' { assert kept == 0 } else { assert kept <= 64 }
				// The unchanged signed-index decoder retains one byte per call.
				// Permit only that isolated residual, never configuration/result
				// buffers or error-interface boxes hidden inside a byte budget.
				for i in 0 .. C.vinix_heap_count() { assert C.vinix_heap_size_at(i) == 1 }
				println('REPOSITORY STATUS signed ' + phase + ': 64 cycles retained ' + kept.str() + ' bytes of isolated index-decoder scratch')
			}
			assert os.read_file(path)! == configuration && os.read_file(directory + '/catalog.json')! == current_cache
			if phase == 'legacy' { assert !os.exists(directory + '/trust-history.json') }
			else { assert os.read_file(directory + '/trust-history.json')! == history }
		}
		legacy := Repository{ id: 'legacy', url: 'file:///retired', public_key: '01' + '00'.repeat(31) }
		legacy_text := canonical_index(Index{ repository: legacy.id, sequence: 42, expires: 1 })!
		legacy_cache := json2.encode([Snapshot{ repository: legacy, text: legacy_text, signature: '01' + '00'.repeat(63) }])
		legacy_history := json2.encode(TrustHistory{ repositories: [RepositoryFloor{ id: legacy.id, public_key: legacy.public_key, sequence: 42, index_sha256: index_digest(legacy_text) }] })
		os.write_file(directory + '/catalog.json', legacy_cache)!; os.write_file(directory + '/trust-history.json', legacy_history)!
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. 64 {
			mut status := repository_status(root)!; assert status.repositories[0].id == 'publisher' && status.history[0].id == 'legacy' && status.history[0].sequence == 42
			retire_repository_status(mut status)
		}
		$if track_heap ? {
			kept := C.vinix_heap_end(); assert kept <= 64
			for i in 0 .. C.vinix_heap_count() { assert C.vinix_heap_size_at(i) == 1 }
			println('REPOSITORY STATUS retired key: 64 cycles retained ' + kept.str() + ' bytes of isolated index-decoder scratch')
		}
		assert os.read_file(directory + '/catalog.json')! == legacy_cache && os.read_file(directory + '/trust-history.json')! == legacy_history
		assert !os.exists(directory + '/current') && os.ls(directory + '/objects')!.len == 0 && os.ls(directory + '/generations')!.len == 0
	}
	println('REPOSITORY STATUS 64-cycle authenticated expired migration, newer floors, signature/equivocation refusals and exact retired-key recovery preserve configuration/cache/history PASS')
}

fn test_repository_status_retires_special_metadata_and_lock_refusals_without_mutation() {
	root := repository_status_fixture()!; defer { os.rmdir_all(root) or {} }
	directory := state_directory(root); guard := acquire(directory)!; guard.release()
	path := root + '/etc/vinix-packages/config.json'; configuration := os.read_file(path)!
	history := '{"format":1,"repositories":[]}'
	os.write_file(directory + '/catalog.json', '[]')!; os.write_file(directory + '/trust-history.json', history)!
	partial := directory + '/objects/' + 'a'.repeat(64) + '.part'; os.write_file(partial, 'retained download')!
	os.mkdir(directory + '/generations/.stage-retained')!; os.write_file(directory + '/generations/.stage-retained/keep', 'retained staging')!
	for failure in ['config-schema', 'cache-schema', 'history-schema', 'config-alias', 'cache-alias', 'history-alias',
		'config-fifo', 'cache-fifo', 'history-fifo', 'lock-alias', 'lock-missing', 'busy']! {
		target := if failure.starts_with('config') || failure == 'busy' { path } else if failure.starts_with('cache') { directory + '/catalog.json' }
			else if failure.starts_with('history') { directory + '/trust-history.json' } else { directory + '/lock' }
		mut writer := Lock{ fd: -1 }
		if failure.ends_with('schema') { os.write_file(target, '{damaged metadata')! }
		else if failure.ends_with('alias') { os.rm(target)!; os.symlink(root + '/missing', target)! }
		else if failure.ends_with('fifo') { os.rm(target)!; assert C.mkfifo(target.str, 0o600) == 0 }
		else if failure == 'lock-missing' { os.rm(target)! }
		else { writer = acquire(directory)! }
		if failure.starts_with('lock') || failure == 'busy' { os.write_file(path, '{must not be parsed')! }
		expected := if failure == 'busy' { 'another package transaction' } else if failure.starts_with('lock') { 'state is unavailable' } else { '' }
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. 1000 { repository_status_refusal(root, expected) }
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, failure + ' retained ' + kept.str() }
		if failure == 'busy' { writer.release() }
		if failure.ends_with('schema') { assert os.read_file(target)! == '{damaged metadata' }
		if failure.ends_with('alias') { assert os.readlink(target)! == root + '/missing'; os.rm(target)! }
		if failure.ends_with('fifo') { assert os.lstat(target)!.mode & 0o170000 == 0o010000; os.rm(target)! }
		if failure.starts_with('lock') { os.write_file(directory + '/lock', '')!; os.chmod(directory + '/lock', 0o644)! }
		os.write_file(path, configuration)!; os.write_file(directory + '/catalog.json', '[]')!; os.write_file(directory + '/trust-history.json', history)!
		mut restored := repository_status(root)!; retire_repository_status(mut restored)
		assert os.read_file(partial)! == 'retained download' && os.read_file(directory + '/generations/.stage-retained/keep')! == 'retained staging'
	}
	assert os.read_file(path)! == configuration && os.read_file(directory + '/catalog.json')! == '[]' && os.read_file(directory + '/trust-history.json')! == history
	assert !os.exists(directory + '/current') && !os.exists(directory + '/refresh') && !os.exists(directory + '/enrollment')
	println('REPOSITORY STATUS 1000 schema/alias/FIFO configuration/cache/history and missing/unsafe/busy lock refusals retire scratch, preserve recovery data and permit restored retry PASS')
}

fn repository_status_fixture() !string {
	root := os.temp_dir() + '/vinix-repository-status-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(root + '/etc/vinix-packages')!
	config := Config{ architecture: 'aarch64', launch_user: 'alex', repositories: [Repository{ id: 'publisher', url: 'file:///repository', public_key: 'a'.repeat(64) }],
		policy: Policy{ allowed: ['app'], pins: [Dependency{ id: 'app', minimum: '1.0.0' }], permissions: ['files'], licenses: ['Vendor é🚀'], reserve_bytes: 7 } }
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(config))!
	return root
}

fn retire_repository_status(mut document RepositoryStatus) {
	document.close(); document.close()
	assert document.architecture == '' && document.repositories.len == 0 && document.history.len == 0
}

fn test_repository_status_retires_results_and_observation_scratch() {
	$if track_heap ? {
		mut retained := u64(0)
		for mode in ['fresh', 'retained', 'bad-cache', 'bad-history']! {
			root := repository_status_fixture()!; defer { os.rmdir_all(root) or {} }
			directory := state_directory(root)
			if mode != 'fresh' {
				guard := acquire(directory)!; guard.release()
				os.write_file(directory + '/trust-history.json', json2.encode(TrustHistory{ repositories: [RepositoryFloor{ id: 'publisher', public_key: 'a'.repeat(64), sequence: 7, index_sha256: 'b'.repeat(64) }] }))!
			}
			if mode == 'bad-cache' { os.write_file(directory + '/catalog.json', '{broken cache')! }
			if mode == 'bad-history' { os.write_file(directory + '/trust-history.json', '{broken history')! }
			C.vinix_heap_begin()
			for _ in 0 .. 1000 {
				if mut document := repository_status(root) { assert mode in ['fresh', 'retained']!; retire_repository_status(mut document) }
				else { message := err.msg(); assert mode !in ['fresh', 'retained']! && message != ''; unsafe { message.free(); err.free() } }
			}
			kept := C.vinix_heap_end(); retained += kept
			println('REPOSITORY STATUS 1000 ' + mode + ' reads/retirements retained ' + kept.str() + ' bytes')
		}
		assert retained == 0
	}
}
