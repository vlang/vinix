// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os
import time
import tools.packages.pkgprotocol

fn rollback_fixture(architecture string) !(string, Service) {
	work := os.temp_dir() + '/vinix-rollback-transaction-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/root/etc/vinix-packages')!
	key := keygen(work + '/seed')!
	config := Config{ architecture: architecture, policy: Policy{ offline: true, reserve_bytes: 0 },
		repositories: [Repository{ id: 'trusted', url: 'file://' + work + '/repository', public_key: key }] }
	os.write_file(work + '/root/etc/vinix-packages/config.json', json2.encode(config))!
	service := Service{ root: work + '/root' }
	for version in 1 .. 5 {
		os.mkdir_all(work + '/source/bin')!
		os.write_file(work + '/source/bin/app', 'signed version ' + version.str())!
		os.chmod(work + '/source/bin/app', 0o755)!
		os.write_file(work + '/manifest.json', json2.encode(Package{ id: 'app', name: 'Application', license: 'MIT',
			version: version.str() + '.0.0', architecture: architecture, kind: 'native', entrypoint: 'bin/app' }))!
		pack(work + '/manifest.json', work + '/source', work + '/repository')!
		publish(work + '/repository', 'trusted', work + '/seed', u64(version), time.now().unix() + 3600)!
		service.refresh()!
		state := service.transact(if version == 1 { 'install' } else { 'upgrade' },
			if version == 1 { ['app'] } else { []string{} }, TransactionOptions{})!
		assert state.generation == u64(version)
	}
	return work, service
}

fn test_rollback_after_cleanup_preserves_a_complete_reversible_history_edge() {
	for architecture in ['aarch64', 'x86_64'] {
		work, service := rollback_fixture(architecture)!; defer { os.rmdir_all(work) or {} }
		directory := state_directory(service.root)
		config := load_config(service.root)!
		defer { close_decoded_configuration(config) }
		collect(config, directory)!
		assert !os.exists(directory + '/generations/2')
		before := read_state(directory, architecture)!
		old_text := os.read_file(directory + '/generations/3/state.json')!
		current_text := os.read_file(directory + '/generations/4/state.json')!
		old := decode_persistent_state(old_text, architecture)!
		legacy := json2.encode(ReviewIdentity{ format: 1, config: config, operation: 'rollback', current: before,
			plan: Plan{ requested: old.requested, packages: old.packages }, target_generation: 3 })
		mut stale := false
		service.rollback(sha256.sum(legacy.bytes()).hex()) or { stale = err.msg().contains('stale') }
		assert stale && service.state()!.generation == 4
		// Rollback is local recovery: no cache, catalog or repository is needed.
		for name in os.ls(directory + '/objects')! { os.rm(directory + '/objects/' + name)! }
		os.rmdir_all(work + '/repository')!
		os.write_file(directory + '/catalog.json', 'unavailable catalog')!
		os.write_file(directory + '/trust-history.json', 'unavailable replay history')!
		personal := work + '/root/home/user/.local/share/vinix-apps/app'
		os.mkdir_all(personal)!; os.write_file(personal + '/note', 'personal data')!
		mut review := service.review('rollback', [])!; defer { review.close() }
		assert review.target_generation == 3 && review.generation == 4
		assert review.disk_needed == u64(4 * 1024 * 1024 + 8192) + before.packages[0].package.files[0].bytes
		restored := service.rollback(review.fingerprint)!
		// This used to activate generation 3, whose previous=2 had been deleted.
		// Cleanup then failed reading that missing state, leaving a broken edge.
		mut cleanup := service.review_cleanup()!; defer { cleanup.close() }
		assert restored.generation == 5 && restored.previous == before.generation
		assert restored.requested == before.requested && restored.packages[0].package.version == '3.0.0'
		assert os.read_file(directory + '/generations/3/state.json')! == old_text
		assert os.read_file(directory + '/generations/4/state.json')! == current_text
		assert os.lstat(directory + '/generations/3/apps/app/bin/app')!.inode != os.lstat(directory + '/generations/5/apps/app/bin/app')!.inode
		if _ := service.rollback(review.fingerprint) { assert false, 'reused rollback approval accepted' }
		assert cleanup.generation == 5 && cleanup.previous == 4 && cleanup.generations == [u64(3)]
		service.apply_cleanup(cleanup.fingerprint)!
		assert !os.exists(directory + '/generations/3')
		undone := service.rollback('')!
		assert undone.generation == 6 && undone.previous == 5 && undone.packages == before.packages
		collect(config, directory)!
		assert service.verify()!.generation == 6
		assert read_generation_state(directory, architecture, 5)!.packages == restored.packages
		assert os.read_file(directory + '/catalog.json')! == 'unavailable catalog'
		assert os.read_file(directory + '/trust-history.json')! == 'unavailable replay history'
		assert os.read_file(personal + '/note')! == 'personal data' && os.ls(directory + '/objects')!.len == 0
	}
	println('ROLLBACK TRANSACTION cleanup before/after rollback retains a complete reversible history edge on both architectures PASS')
}

fn test_rollback_disk_refusal_precedes_recovery_and_preserves_current_and_previous() {
	work, service := rollback_fixture('aarch64')!; defer { os.rmdir_all(work) or {} }
	directory := state_directory(service.root)
	config := load_config(service.root)!
	reserve := u64(1024) * 1024 * 1024 * 1024
	assert free_bytes(directory)! < reserve, 'disk refusal fixture requires less than the supported 1 TiB reserve'
	limited := Config{ ...config, policy: Policy{ ...config.policy, reserve_bytes: reserve } }
	os.write_file(service.root + '/etc/vinix-packages/config.json', json2.encode(limited))!
	os.mkdir(directory + '/generations/.stage-sentinel')!
	os.write_file(directory + '/generations/.stage-sentinel/keep', 'recovery data')!
	mut review := service.review('rollback', [])!; defer { review.close() }
	assert review.disk_needed > 4 * 1024 * 1024 && review.disk_reserve == reserve
	mut refused := false
	service.rollback(review.fingerprint) or {
		message := err.msg(); refused = message.contains('insufficient disk space')
		unsafe { message.free(); err.free() }
	}
	assert refused && service.verify()!.generation == 4
	assert os.read_file(directory + '/generations/.stage-sentinel/keep')! == 'recovery data'
	assert !os.exists(directory + '/generations/5') && !os.exists(directory + '/generations/.stage-5')
	assert read_generation_state(directory, 'aarch64', 3)!.packages[0].package.version == '3.0.0'
	os.write_file(service.root + '/etc/vinix-packages/config.json', json2.encode(config))!
	assert service.rollback('')!.generation == 5
	println('ROLLBACK TRANSACTION exact retained-source disk estimate and reserve refusal preserve activation, rollback and interrupted work PASS')
}

fn rollback_damage_published(phase string) {
	if phase != 'published' { return }
	path := os.getenv('VINIX_ROLLBACK_TEST_DIRECTORY') + '/generations/5/apps/app/bin/app'
	os.write_file(path, 'damaged published copy') or { panic(err) }
}

fn rollback_no_acquisition(event pkgprotocol.Progress) {
	assert event.phase !in ['download', 'download-restart', 'download-resume']
}

fn test_rollback_interruption_and_published_failure_retry_at_a_safe_identity() {
	for published_failure in [false, true] {
		work, service := rollback_fixture('aarch64')!; defer { os.rmdir_all(work) or {} }
		directory := state_directory(service.root)
		config := load_config(service.root)!
		mut review := service.review('rollback', [])!; defer { review.close() }
		os.setenv('VINIX_ROLLBACK_TEST_DIRECTORY', directory, true)
		guard := acquire(directory)!
		mut refused := false
		rollback_transaction_locked(config, directory, TransactionOptions{ expected_review: review.fingerprint,
			stop_before_activation: !published_failure, checkpoint: rollback_damage_published,
			progress: rollback_no_acquisition }) or { refused = true; unsafe { err.free() } }
		guard.release(); os.unsetenv('VINIX_ROLLBACK_TEST_DIRECTORY')
		assert refused && service.verify()!.generation == 4
		assert os.exists(directory + '/generations/.stage-5') == !published_failure
		assert os.exists(directory + '/generations/5') == published_failure
		for name in os.ls(directory + '/objects')! { os.rm(directory + '/objects/' + name)! }
		os.rmdir_all(work + '/repository')!
		retry := Service{ ...service, progress: rollback_no_acquisition }.rollback(review.fingerprint)!
		assert retry.generation == if published_failure { u64(6) } else { u64(5) }
		assert retry.previous == 4 && retry.packages[0].package.version == '3.0.0'
		assert !os.exists(directory + '/generations/.stage-5')
		assert read_generation_state(directory, 'aarch64', 3)!.packages == retry.packages
	}
	println('ROLLBACK TRANSACTION interrupted staging and damaged published copy preserve current; reviewed retry uses retained source without acquisition PASS')
}

fn test_rollback_to_empty_set_and_equal_manifests_still_retains_the_replaced_generation() {
	work, service := rollback_fixture('aarch64')!; defer { os.rmdir_all(work) or {} }
	directory := state_directory(service.root)
	service.transact('remove', ['app'], TransactionOptions{})!
	assert service.rollback('')!.generation == 6 && service.state()!.packages.len == 1
	assert service.rollback('')!.generation == 7 && service.state()!.packages.len == 0
	// Legacy history can contain equal package sets. Restoring it must still
	// repair the temporal history edge rather than returning an unchanged state.
	current := service.state()!
	state := State{ ...current, packages: [], requested: [] }
	previous := State{ ...state, generation: 6, previous: 4 }
	root := directory + '/generations/6'
	os.rmdir_all(root + '/apps')!; os.mkdir(root + '/apps')!
	os.rm(root + '/share/applications/vinix-app.desktop')!
	os.write_file(root + '/state.json', encode_generation_state(previous)!)!
	mut review := service.review('rollback', [])!; defer { review.close() }
	assert review.rows.len == 0 && review.disk_needed == 4 * 1024 * 1024
	equal := service.rollback(review.fingerprint)!
	assert equal.generation == 8 && equal.previous == 7 && equal.packages.len == 0
	println('ROLLBACK TRANSACTION empty and identical package sets still publish a fresh reversible generation PASS')
}
