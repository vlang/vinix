// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.signing as ed25519
import json2
import os
import time

fn administration_root(label string) !string {
	root := os.real_path(os.temp_dir()) + '/vinix-repository-' + label + '-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(root + '/etc/vinix-packages')!
	os.chmod(root + '/etc/vinix-packages', 0o755)!
	config := Config{
		architecture: 'aarch64'
		launch_user:  'alex'
		policy:       Policy{
			offline:       true
			reserve_bytes: 1234
			allowed:       ['editor']
			pins:          [Dependency{ id: 'editor', before: '2.0.0' }]
			permissions:   ['files']
			licenses:      ['Vendor-EULA']
		}
	}
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(config))!
	os.chmod(root + '/etc/vinix-packages/config.json', 0o644)!
	return root
}

fn administration_index(path string, private_key ed25519.PrivateKey, sequence u64, expires i64, suffix string) !string {
	os.mkdir_all(path)!
	text := canonical_index(Index{ repository: 'fixture', sequence: sequence, expires: expires })! + suffix
	os.write_file(path + '/index.json', text)!
	os.write_file(path + '/index.sig', ed25519.sign(private_key, text.bytes())!.hex())!
	return text
}

fn test_enrollment_authenticates_before_trusting_and_preserves_policy() {
	root := administration_root('enrollment')!
	defer { os.rmdir_all(root) or {} }
	before := load_config(root)!
	assert repository_status(root)!.repositories.len == 0
	assert !os.exists(state_directory(root))
	key, secret := ed25519.generate_key()!
	repository := Repository{ id: 'fixture', url: 'file://' + root + '/repo', public_key: key.hex() }
	administration_index(root + '/repo', secret, 10, time.now().unix() + 3600, '')!
	result := enroll_repository(root, repository, false)!
	assert result.repositories == [repository]
	assert result.policy == before.policy && result.launch_user == 'alex'
	assert result.architecture == before.architecture && result.format == before.format
	assert os.stat(root + '/etc/vinix-packages/config.json')!.mode & 0o777 == 0o644
	status := repository_status(root)!
	assert status.format == 1 && status.architecture == 'aarch64'
	assert status.repositories == [repository] && status.history.len == 1
	assert status.history[0].sequence == 10 && status.history[0].public_key == key.hex()
	assert read_state(state_directory(root), 'aarch64')!.generation == 0
	assert os.ls(state_directory(root) + '/objects')!.len == 0
	assert !os.exists(state_directory(root) + '/catalog.json')
	// Enrollment proves possession but only update publishes the catalog.
	if _ := load_catalog(result, state_directory(root)) {
		assert false
	}
	refresh(result, state_directory(root))!
	assert load_catalog(result, state_directory(root))!.packages.len == 0
}

fn test_rejected_enrollment_keeps_configuration_and_history_unchanged() {
	root := administration_root('refusal')!
	defer { os.rmdir_all(root) or {} }
	key, secret := ed25519.generate_key()!
	other_key, _ := ed25519.generate_key()!
	path := root + '/repo'
	repository := Repository{ id: 'fixture', url: 'file://' + path, public_key: key.hex() }
	expires := time.now().unix() + 3600
	text := administration_index(path, secret, 10, expires, '')!
	enroll_repository(root, repository, false)!
	configuration := os.read_file(root + '/etc/vinix-packages/config.json')!
	history := os.read_file(state_directory(root) + '/trust-history.json')!
	for bad in [Repository{ ...repository, public_key: other_key.hex() },
		Repository{ ...repository, id: 'other' }, Repository{ ...repository, id: '../escape' },
		Repository{ ...repository, url: 'http://example.invalid' },
		Repository{ ...repository, url: 'https://example.invalid' }] {
		if _ := enroll_repository(root, bad, false) {
			assert false, 'accepted unauthenticated repository'
		}
		assert os.read_file(root + '/etc/vinix-packages/config.json')! == configuration
		assert os.read_file(state_directory(root) + '/trust-history.json')! == history
	}
	for invalid in ['00'.repeat(64), 'not-hex'] {
		os.write_file(path + '/index.sig', invalid)!
		if _ := enroll_repository(root, repository, false) {
			assert false
		}
	}
	os.write_file(path + '/index.json', text + ' ')!
	os.write_file(path + '/index.sig', ed25519.sign(secret, text.bytes())!.hex())!
	if _ := enroll_repository(root, repository, false) {
		assert false, 'accepted changed signed bytes'
	}
	for invalid_text in ['not JSON',
		administration_index(path, secret, 11, time.now().unix() - 1, '')!] {
		os.write_file(path + '/index.json', invalid_text)!
		os.write_file(path + '/index.sig', ed25519.sign(secret, invalid_text.bytes())!.hex())!
		if _ := enroll_repository(root, repository, false) {
			assert false, 'accepted invalid authenticated metadata'
		}
	}
	assert os.read_file(root + '/etc/vinix-packages/config.json')! == configuration
	assert os.read_file(state_directory(root) + '/trust-history.json')! == history
	assert !os.exists(state_directory(root) + '/enrollment')
}

fn test_revocation_empty_refresh_and_mirror_changes_retain_replay_floor() {
	root := administration_root('revocation')!
	defer { os.rmdir_all(root) or {} }
	key, secret := ed25519.generate_key()!
	path := root + '/repo'
	repository := Repository{ id: 'fixture', url: 'file://' + path, public_key: key.hex() }
	expires := time.now().unix() + 3600
	administration_index(path, secret, 10, expires, '')!
	enrolled := enroll_repository(root, repository, false)!
	refresh(enrolled, state_directory(root))!
	history := os.read_file(state_directory(root) + '/trust-history.json')!
	revoked := revoke_repository(root, 'fixture')!
	assert revoked.repositories.len == 0 && revoked.policy == enrolled.policy
	refresh(revoked, state_directory(root))!
	assert read_snapshots(state_directory(root))!.len == 0
	assert os.read_file(state_directory(root) + '/trust-history.json')! == history
	for sequence in [u64(9), 10] {
		// Sequence 10 is also refused if exact signed bytes have changed.
		administration_index(path, secret, sequence, expires, ' ')!
		if _ := enroll_repository(root, repository, false) {
			assert false, 'forgot retained replay floor'
		}
		assert load_config(root)!.repositories.len == 0
		assert os.read_file(state_directory(root) + '/trust-history.json')! == history
	}
	administration_index(root + '/mirror', secret, 9, expires, '')!
	mirror := Repository{ ...repository, url: 'file://' + root + '/mirror' }
	if _ := enroll_repository(root, mirror, true) {
		assert false, 'URL change reset publisher history'
	}
	administration_index(root + '/mirror', secret, 11, expires, '')!
	enroll_repository(root, mirror, true)!
	assert repository_status(root)!.history[0].sequence == 11
	refresh(load_config(root)!, state_directory(root))!
}

fn test_explicit_key_rotation_retains_old_key_history() {
	root := administration_root('rotation')!
	defer { os.rmdir_all(root) or {} }
	key, secret := ed25519.generate_key()!
	new_key, new_secret := ed25519.generate_key()!
	path := root + '/repo'
	repository := Repository{ id: 'fixture', url: 'file://' + path, public_key: key.hex() }
	expires := time.now().unix() + 3600
	administration_index(path, secret, 10, expires, '')!
	enroll_repository(root, repository, false)!
	administration_index(path, new_secret, 1, expires, '')!
	replacement := Repository{ ...repository, public_key: new_key.hex() }
	enroll_repository(root, replacement, false)!
	assert repository_status(root)!.history.len == 2
	administration_index(path, secret, 9, expires, '')!
	if _ := enroll_repository(root, repository, false) {
		assert false, 'key rotation forgot old publisher floor'
	}
	assert load_config(root)!.repositories == [replacement]
	administration_index(path, secret, 11, expires, '')!
	enroll_repository(root, repository, false)!
	assert repository_status(root)!.history.len == 2
}

fn test_interrupted_cache_publication_refuses_older_catalog_and_recovers() {
	root := administration_root('publication')!
	defer { os.rmdir_all(root) or {} }
	key, secret := ed25519.generate_key()!
	path := root + '/repo'
	repository := Repository{ id: 'fixture', url: 'file://' + path, public_key: key.hex() }
	expires := time.now().unix() + 3600
	administration_index(path, secret, 1, expires, '')!
	config := enroll_repository(root, repository, false)!
	directory := state_directory(root)
	refresh(config, directory)!
	old_catalog := os.read_file(directory + '/catalog.json')!
	// Simulate a cut after durable history publication and before catalog rename.
	text := administration_index(path, secret, 2, expires, '')!
	index := verify_index(repository, text, os.read_file(path + '/index.sig')!, time.now().unix())!
	save_history(directory, remember_index(read_history(directory)!, repository, index, text)!)!
	if _ := load_catalog(config, directory) {
		assert false, 'used cache older than durable floor'
	}
	assert os.read_file(directory + '/catalog.json')! == old_catalog
	refresh(config, directory)!
	assert load_catalog(config, directory)!.packages.len == 0
	assert read_snapshots(directory)![0].text == text
	assert read_history(directory)!.repositories[0].sequence == 2
}

fn test_legacy_expired_snapshots_migrate_even_when_repository_revoked() {
	root := administration_root('legacy')!
	defer { os.rmdir_all(root) or {} }
	key, secret := ed25519.generate_key()!
	repository := Repository{ id: 'fixture', url: 'file://' + root + '/repo', public_key: key.hex() }
	text := administration_index(root + '/repo', secret, 12, time.now().unix() - 1, '')!
	directory := state_directory(root)
	guard := acquire(directory)!
	guard.release()
	atomic_write(directory + '/catalog.json', json2.encode([Snapshot{
		repository: repository
		text:       text
		signature:  os.read_file(root + '/repo/index.sig')!
	}]))!
	assert !os.exists(directory + '/trust-history.json')
	refresh(load_config(root)!, directory)!
	assert read_snapshots(directory)!.len == 0
	assert read_history(directory)!.repositories[0].sequence == 12
	administration_index(root + '/repo', secret, 11, time.now().unix() + 3600, '')!
	if _ := enroll_repository(root, repository, false) {
		assert false, 'legacy expiry reset replay floor'
	}
}

fn test_interrupted_enrollment_keeps_trust_disabled_and_rejects_replay() {
	root := administration_root('enrollment-cut')!
	defer { os.rmdir_all(root) or {} }
	key, secret := ed25519.generate_key()!
	path := root + '/repo'
	repository := Repository{ id: 'fixture', url: 'file://' + path, public_key: key.hex() }
	expires := time.now().unix() + 3600
	text := administration_index(path, secret, 2, expires, '')!
	directory := state_directory(root)
	guard := acquire(directory)!
	guard.release()
	index := verify_index(repository, text, os.read_file(path + '/index.sig')!, time.now().unix())!
	// Simulate a cut between durable history and configuration publication.
	save_history(directory, remember_index(TrustHistory{}, repository, index, text)!)!
	assert load_config(root)!.repositories.len == 0
	assert repository_status(root)!.history[0].sequence == 2
	assert !os.exists(directory + '/catalog.json')
	administration_index(path, secret, 1, expires, '')!
	if _ := enroll_repository(root, repository, false) {
		assert false, 'interrupted enrollment accepted an older index'
	}
	assert load_config(root)!.repositories.len == 0
	administration_index(path, secret, 2, expires, '')!
	enroll_repository(root, repository, false)!
	assert load_config(root)!.repositories == [repository]
	assert read_state(directory, 'aarch64')!.generation == 0
}

fn test_failed_combined_refresh_does_not_advance_any_floor() {
	root := administration_root('refresh')!
	defer { os.rmdir_all(root) or {} }
	key, secret := ed25519.generate_key()!
	repository := Repository{ id: 'fixture', url: 'file://' + root + '/repo', public_key: key.hex() }
	expires := time.now().unix() + 3600
	administration_index(root + '/repo', secret, 1, expires, '')!
	config := enroll_repository(root, repository, false)!
	directory := state_directory(root)
	refresh(config, directory)!
	history := os.read_file(directory + '/trust-history.json')!
	cache := os.read_file(directory + '/catalog.json')!
	administration_index(root + '/repo', secret, 2, expires, '')!
	unreachable := Repository{ ...repository, id: 'unreachable', url: 'file://' + root + '/missing' }
	if _ := refresh(Config{ ...config, repositories: [repository, unreachable] }, directory) {
		assert false
	}
	assert os.read_file(directory + '/trust-history.json')! == history
	assert os.read_file(directory + '/catalog.json')! == cache
	assert load_catalog(config, directory)!.packages.len == 0
}

fn test_administration_rejects_unsafe_configuration_and_ignores_predictable_temporary_links() {
	root := administration_root('safe-write')!
	defer { os.rmdir_all(root) or {} }
	key, secret := ed25519.generate_key()!
	repository := Repository{ id: 'fixture', url: 'file://' + root + '/repo', public_key: key.hex() }
	administration_index(root + '/repo', secret, 1, time.now().unix() + 3600, '')!
	path := root + '/etc/vinix-packages/config.json'
	original := os.read_file(path)!
	os.chmod(path, 0o666)!
	if _ := enroll_repository(root, repository, false) {
		assert false
	}
	assert os.read_file(path)! == original
	os.chmod(path, 0o644)!
	os.chmod(os.dir(path), 0o777)!
	if _ := enroll_repository(root, repository, false) {
		assert false
	}
	os.chmod(os.dir(path), 0o755)!
	os.rename(path, root + '/real-config.json')!
	os.symlink(root + '/real-config.json', path)!
	if _ := enroll_repository(root, repository, false) {
		assert false
	}
	assert os.read_file(root + '/real-config.json')! == original
	os.rm(path)!
	os.rename(root + '/real-config.json', path)!
	os.write_file(root + '/victim', 'do not overwrite')!
	os.symlink(root + '/victim', path + '.new')!
	enroll_repository(root, repository, false)!
	os.symlink(root + '/victim', state_directory(root) + '/trust-history.json.new')!
	enroll_repository(root, repository, false)!
	assert os.read_file(root + '/victim')! == 'do not overwrite'
	assert os.is_link(path + '.new')
	assert os.ls(os.dir(path))!.all(!it.starts_with('.administration-') && !it.starts_with('.package-'))
	assert os.ls(state_directory(root))!.all(!it.starts_with('.package-'))
	guard := acquire(state_directory(root))!
	if _ := repository_status(root) {
		assert false, 'listing bypassed package writer lock'
	}
	guard.release()
	// Revocation must succeed despite unreachable/corrupt repository metadata.
	os.write_file(state_directory(root) + '/catalog.json', 'corrupt catalog')!
	os.rmdir_all(root + '/repo')!
	revoke_repository(root, 'fixture')!
	assert load_config(root)!.repositories.len == 0
	if _ := revoke_repository(root, 'fixture') {
		assert false
	}
}

fn test_invalid_persistent_history_fails_closed() {
	root := administration_root('invalid-history')!
	defer { os.rmdir_all(root) or {} }
	key, secret := ed25519.generate_key()!
	repository := Repository{ id: 'fixture', url: 'file://' + root + '/repo', public_key: key.hex() }
	administration_index(root + '/repo', secret, 1, time.now().unix() + 3600, '')!
	enroll_repository(root, repository, false)!
	directory := state_directory(root)
	floor := read_history(directory)!.repositories[0]
	for invalid in [json2.encode(TrustHistory{ format: 2, repositories: [floor] }),
		json2.encode(TrustHistory{ repositories: [floor, floor] }),
		json2.encode(TrustHistory{ repositories: [RepositoryFloor{ ...floor, sequence: 0 }] }),
		json2.encode(TrustHistory{ repositories: [RepositoryFloor{ ...floor, index_sha256: 'not-a-digest' }] }),
		'{"format":1}', '{"format":1,"repositories":null}'] {
		os.write_file(directory + '/trust-history.json', invalid)!
		if _ := enroll_repository(root, repository, false) {
			assert false
		}
		if _ := refresh(load_config(root)!, directory) {
			assert false
		}
		assert load_config(root)!.repositories == [repository]
		assert os.read_file(directory + '/trust-history.json')! == invalid
	}
	// Invalid history cannot prevent an administrator revoking a publisher.
	revoke_repository(root, 'fixture')!
}

fn test_repository_review_is_read_only_and_apply_binds_catalog_and_configuration() {
	root := administration_root('review')!
	defer { os.rmdir_all(root) or {} }
	key, secret := ed25519.generate_key()!
	path := root + '/repo with spaces'
	repository := Repository{ id: 'fixture', url: 'file://' + path, public_key: key.hex() }
	expires := time.now().unix() + 3600
	first := administration_index(path, secret, 1, expires, '')!
	configuration := os.read_file(root + '/etc/vinix-packages/config.json')!
	mut review := review_repository(root, 'enroll', repository, false)!
	defer { review.close() }
	assert review.sequence == 1 && review.expires == expires && review.package_count == 0
	assert review.previous_public_key == '' && review.remembered_sequence == 0
	assert os.read_file(root + '/etc/vinix-packages/config.json')! == configuration
	assert !os.exists(state_directory(root))
	// Even same-sequence changed bytes cannot consume the old review.
	administration_index(path, secret, 1, expires, ' ')!
	mut refused := false
	enroll_repository_reviewed(root, repository, false, review.fingerprint) or { refused = err.msg().contains('stale') }
	assert refused && os.read_file(root + '/etc/vinix-packages/config.json')! == configuration
	assert !os.exists(state_directory(root) + '/trust-history.json')
	os.write_file(path + '/index.json', first)!
	os.write_file(path + '/index.sig', ed25519.sign(secret, first.bytes())!.hex())!
	enroll_repository_reviewed(root, repository, false, review.fingerprint)!
	assert load_config(root)!.repositories == [repository]
	assert read_state(state_directory(root), 'aarch64')!.generation == 0
	refused = false
	enroll_repository_reviewed(root, repository, false, review.fingerprint) or { refused = err.msg().contains('stale') }
	assert refused
	mut revocation := review_repository(root, 'revoke', Repository{ id: repository.id }, false)!
	defer { revocation.close() }
	current := load_config(root)!
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(Config{ ...current, launch_user: 'bob' }))!
	refused = false
	revoke_repository_reviewed(root, repository.id, revocation.fingerprint) or { refused = err.msg().contains('stale') }
	assert refused && load_config(root)!.repositories.len == 1
}

fn test_repository_review_floor_changes_and_intent_are_checked_before_trust_publication() {
	root := administration_root('review-floor')!
	defer { os.rmdir_all(root) or {} }
	key, secret := ed25519.generate_key()!
	repository := Repository{ id: 'fixture', url: 'file://' + root + '/repo', public_key: key.hex() }
	expires := time.now().unix() + 3600
	administration_index(root + '/repo', secret, 1, expires, '')!
	config := enroll_repository(root, repository, false)!
	refresh(config, state_directory(root))!
	administration_index(root + '/repo', secret, 2, expires, '')!
	mut review := review_repository(root, 'enroll', repository, false)!
	defer { review.close() }
	assert review.remembered_sequence == 1 && review.previous_public_key == repository.public_key
	refresh(config, state_directory(root))!
	history := os.read_file(state_directory(root) + '/trust-history.json')!
	mut refused := false
	enroll_repository_reviewed(root, repository, false, review.fingerprint) or { refused = err.msg().contains('stale') }
	assert refused && os.read_file(state_directory(root) + '/trust-history.json')! == history
	mut fresh := review_repository(root, 'enroll', repository, false)!
	defer { fresh.close() }
	refused = false
	revoke_repository_reviewed(root, repository.id, fresh.fingerprint) or { refused = err.msg().contains('stale') }
	assert refused && load_config(root)!.repositories == [repository]
	enroll_repository_reviewed(root, repository, false, fresh.fingerprint)!
}

fn test_reviewed_revocation_survives_corrupt_metadata_and_refuses_replaced_key() {
	root := administration_root('review-revoke')!
	defer { os.rmdir_all(root) or {} }
	key, secret := ed25519.generate_key()!
	new_key, new_secret := ed25519.generate_key()!
	repository := Repository{ id: 'fixture', url: 'file://' + root + '/repo', public_key: key.hex() }
	expires := time.now().unix() + 3600
	administration_index(root + '/repo', secret, 1, expires, '')!
	enroll_repository(root, repository, false)!
	mut old := review_repository(root, 'revoke', Repository{ id: repository.id }, false)!
	defer { old.close() }
	administration_index(root + '/repo', new_secret, 1, expires, '')!
	enroll_repository(root, Repository{ ...repository, public_key: new_key.hex() }, false)!
	mut refused := false
	revoke_repository_reviewed(root, repository.id, old.fingerprint) or { refused = err.msg().contains('stale') }
	assert refused && load_config(root)!.repositories[0].public_key == new_key.hex()
	os.write_file(state_directory(root) + '/catalog.json', 'corrupt catalog')!
	os.write_file(state_directory(root) + '/trust-history.json', 'corrupt history')!
	os.rmdir_all(root + '/repo')!
	mut fresh := review_repository(root, 'revoke', Repository{ id: repository.id }, false)!
	defer { fresh.close() }
	assert fresh.public_key == new_key.hex() && fresh.index_sha256 == '' && fresh.sequence == 0
	revoke_repository_reviewed(root, repository.id, fresh.fingerprint)!
	assert load_config(root)!.repositories.len == 0
	assert os.read_file(state_directory(root) + '/trust-history.json')! == 'corrupt history'
}
