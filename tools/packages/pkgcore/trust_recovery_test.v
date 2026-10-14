// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import tools.packages.signing

fn retirement_fixture() (Snapshot, TrustHistory) {
	repository := Repository{ id: 'legacy', url: 'file:///offline/legacy', public_key: '01' + '00'.repeat(31) }
	text := canonical_index(Index{ repository: 'legacy', sequence: 42, expires: 1 }) or { panic(err) }
	snapshot := Snapshot{ repository: repository, text: text, signature: '01' + '00'.repeat(63) }
	return snapshot, TrustHistory{ repositories: [RepositoryFloor{ id: 'legacy', public_key: repository.public_key,
		sequence: 42, index_sha256: index_digest(text) }] }
}

fn test_retired_invalid_cache_requires_exact_preexisting_history_and_disabled_identity() {
	snapshot, history := retirement_fixture()
	config := Config{ architecture: 'aarch64' }
	assert recorded_retired_snapshot(config, history, snapshot)
	assert !recorded_retired_snapshot(Config{ ...config, repositories: [snapshot.repository] }, history, snapshot)
	// A mirror/URL change alone does not revoke the old ID/key.
	assert !recorded_retired_snapshot(Config{ ...config, repositories: [Repository{ ...snapshot.repository, url: 'file:///new-mirror' }] }, history, snapshot)
	assert !recorded_retired_snapshot(config, TrustHistory{}, snapshot)
	for changed in [RepositoryFloor{ ...history.repositories[0], id: 'other' },
		RepositoryFloor{ ...history.repositories[0], public_key: '00'.repeat(32) },
		RepositoryFloor{ ...history.repositories[0], sequence: 41 },
		RepositoryFloor{ ...history.repositories[0], sequence: 43 },
		RepositoryFloor{ ...history.repositories[0], index_sha256: 'a'.repeat(64) }] {
		assert !recorded_retired_snapshot(config, TrustHistory{ repositories: [changed] }, snapshot)
	}
	assert !recorded_retired_snapshot(config, history, Snapshot{ ...snapshot, text: snapshot.text + ' ' })
	// Even a pinned digest cannot turn malformed/ambiguous index bytes into a
	// recoverable cached record. Existing history is never inferred or repaired.
	for text in ['{}', snapshot.text.replace('"sequence":42', '"sequence":41'),
		snapshot.text.replace('"sequence":42', '"sequence":42,"sequ\\u0065nce":42')] {
		assert text != snapshot.text
		pinned := TrustHistory{ repositories: [RepositoryFloor{ ...history.repositories[0], index_sha256: index_digest(text) }] }
		assert !recorded_retired_snapshot(config, pinned, Snapshot{ ...snapshot, text: text })
	}
	println('TRUST RECOVERY exact disabled identity/digest/sequence and complete index required PASS')
}

fn test_retired_valid_keys_still_require_signatures_even_for_exact_recorded_bytes() {
	key, secret := signing.generate_key()!
	repository := Repository{ id: 'legacy', url: 'file:///offline/legacy', public_key: key.hex() }
	text := canonical_index(Index{ repository: 'legacy', sequence: 42, expires: 1 })!
	snapshot := Snapshot{ repository: repository, text: text, signature: '00'.repeat(64) }
	history := TrustHistory{ repositories: [RepositoryFloor{ id: 'legacy', public_key: repository.public_key,
		sequence: 42, index_sha256: index_digest(text) }] }
	config := Config{ architecture: 'aarch64' }
	assert !recorded_retired_snapshot(config, history, snapshot)
	root := os.real_path(os.temp_dir()) + '/vinix-retirement-signature-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	save_history(root, history)!
	if _ := history_with_snapshots(config, root, [snapshot]) { assert false } else {
		assert err.msg().contains('signature verification failed')
	}
	signed := signing.sign(secret, text.bytes())!.hex()
	assert history_with_snapshots(config, root, [Snapshot{ ...snapshot, signature: signed }])! == history
	println('TRUST RECOVERY valid retired keys still require authenticated signatures PASS')
}

fn test_empty_refresh_retires_recorded_unusable_cache_without_dropping_any_floor() {
	snapshot, recorded := retirement_fixture()
	root := os.real_path(os.temp_dir()) + '/vinix-retirement-refresh-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	history := TrustHistory{ repositories: [recorded.repositories[0], RepositoryFloor{ id: 'other',
		public_key: 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a', sequence: 99, index_sha256: 'a'.repeat(64) }] }
	save_history(root, history)!
	atomic_write(root + '/catalog.json', json2.encode([snapshot]))!
	before := os.read_file(root + '/trust-history.json')!
	config := Config{ architecture: 'aarch64', policy: Policy{ offline: true } }
	assert refresh(config, root)!.packages.len == 0
	assert read_snapshots(root)!.len == 0 && os.read_file(root + '/trust-history.json')! == before
	assert read_history(root)! == history
	println('TRUST RECOVERY empty refresh preserves retired and independent replay floors PASS')
}
