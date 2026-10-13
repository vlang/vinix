// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

fn service_fixture(label string) !(string, Service, Config) {
	work := os.temp_dir() + '/vinix-service-' + label + '-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	root := work + '/root'
	os.mkdir_all(root + '/etc/vinix-packages')!
	os.mkdir_all(work + '/source/bin')!
	os.write_file(work + '/source/bin/app', 'signed application\n')!
	os.chmod(work + '/source/bin/app', 0o755)!
	key := keygen(work + '/seed')!
	config := Config{
		architecture: 'aarch64'
		repositories: [Repository{ id: 'fixture', url: 'file://' + work + '/repository', public_key: key }]
		policy: Policy{ reserve_bytes: 0 }
	}
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(config))!
	p := Package{ id: 'app', version: '1.0.0', architecture: 'aarch64', name: 'Application',
		license: 'MIT', kind: 'native', entrypoint: 'bin/app', permissions: ['files'] }
	os.write_file(work + '/manifest.json', json2.encode(p))!
	pack(work + '/manifest.json', work + '/source', work + '/repository')!
	publish(work + '/repository', 'fixture', work + '/seed', 1, time.now().unix() + 3600)!
	service := Service{ root: root }
	service.refresh()!
	return work, service, config
}

fn test_service_reloads_policy_trust_and_architecture_for_each_locked_operation() {
	work, service, initial := service_fixture('freshness')!
	defer { os.rmdir_all(work) or {} }
	directory := state_directory(service.root)
	path := service.root + '/etc/vinix-packages/config.json'
	mut review := service.review('install', ['app'])!
	defer { review.close() }
	// The client existed before this administration change. Its apply must
	// fingerprint the newly loaded policy before cleaning or acquiring bytes.
	save_configuration(path, Config{ ...initial, policy: Policy{ ...initial.policy, reserve_bytes: 1 } })!
	os.mkdir_all(directory + '/generations/.stage-sentinel')!
	mut refused := false
	service.transact('install', ['app'], TransactionOptions{ expected_review: review.fingerprint }) or { refused = err.msg().contains('stale') }
	assert refused && service.state()!.generation == 0
	assert os.ls(directory + '/objects')!.len == 0 && os.is_dir(directory + '/generations/.stage-sentinel')
	save_configuration(path, Config{ ...initial, policy: Policy{ permissions: [], reserve_bytes: 0 } })!
	refused = false
	service.plan('install', ['app']) or { refused = err.msg().contains('permissions blocked') }
	assert refused
	refused = false
	service.transact('install', ['app'], TransactionOptions{}) or { refused = err.msg().contains('permissions blocked') }
	assert refused && service.state()!.generation == 0
	save_configuration(path, initial)!
	service.transact('install', ['app'], TransactionOptions{ expected_review: review.fingerprint })!
	assert service.verify()!.packages.len == 1
	service.transact('remove', ['app'], TransactionOptions{})!
	assert service.state()!.previous == 1
	revoke_repository(service.root, 'fixture')!
	refused = false
	service.rollback('') or { refused = err.msg().contains('no longer trusted') }
	assert refused && service.state()!.generation == 2
	refused = false
	service.mirror(work + '/revoked-mirror', ['app']) or { refused = true }
	assert refused && !os.exists(work + '/revoked-mirror')
	assert service.refresh()!.packages.len == 0 && read_snapshots(directory)!.len == 0
	assert repository_status(service.root)!.history.len == 1
	save_configuration(path, Config{ ...initial, architecture: 'x86_64' })!
	refused = false
	service.state() or { refused = err.msg().contains('persistent package state') }
	assert refused
	save_configuration(path, initial)!
	assert service.state()!.architecture == 'aarch64'
}

fn service_busy_errors(service Service) ![]string {
	guard := acquire(state_directory(service.root))!
	defer { guard.release() }
	// Loading this first would yield a JSON/configuration error. Every service
	// entry point must report the held writer lock before touching configuration.
	os.write_file(service.root + '/etc/vinix-packages/config.json', '{broken configuration')!
	mut messages := []string{}
	service.refresh() or { messages << err.msg() }
	service.transact('install', ['app'], TransactionOptions{}) or { messages << err.msg() }
	service.deploy(service.root + '/absent-deployment.json') or { messages << err.msg() }
	service.plan('install', ['app']) or { messages << err.msg() }
	service.review('install', ['app']) or { messages << err.msg() }
	service.rollback('') or { messages << err.msg() }
	service.collect() or { messages << err.msg() }
	service.mirror(service.root + '/absent-mirror', ['app']) or { messages << err.msg() }
	service.state() or { messages << err.msg() }
	service.verify() or { messages << err.msg() }
	service.prepare_launch('app') or { messages << err.msg() }
	return messages
}

fn test_service_locks_before_configuration_reads_and_releases_on_errors() {
	work, service, config := service_fixture('busy')!
	defer { os.rmdir_all(work) or {} }
	messages := service_busy_errors(service)!
	assert messages.len == 11 && messages.all(it.contains('another package transaction'))
	mut invalid := false
	service.state() or { invalid = !err.msg().contains('transaction') }
	assert invalid
	save_configuration(service.root + '/etc/vinix-packages/config.json', config)!
	assert service.state()!.generation == 0
	service.refresh()!
	service.transact('install', ['app'], TransactionOptions{})!
	assert service.verify()!.generation == 1
}

fn test_service_offline_overlay_fresh_status_and_unsafe_lock() {
	work, service, initial := service_fixture('offline')!
	defer { os.rmdir_all(work) or {} }
	path := service.root + '/etc/vinix-packages/config.json'
	save_configuration(path, Config{ ...initial, repositories: [Repository{ ...initial.repositories[0], url: 'https://example.invalid' }] })!
	offline := Service{ root: service.root, offline: true }
	mut refused := false
	offline.refresh() or { refused = err.msg().contains('offline mode') }
	assert refused && !load_config(service.root)!.policy.offline
	assert read_snapshots(state_directory(service.root))!.len == 1
	fresh_root := work + '/fresh'
	os.mkdir_all(fresh_root + '/etc/vinix-packages')!
	os.write_file(fresh_root + '/etc/vinix-packages/config.json', json2.encode(Config{ architecture: 'x86_64' }))!
	fresh := Service{ root: fresh_root }
	assert fresh.state()!.generation == 0 && fresh.verify()!.packages.len == 0
	assert !os.exists(state_directory(fresh_root))
	os.mkdir_all(state_directory(fresh_root))!
	os.symlink(work + '/missing-lock', state_directory(fresh_root) + '/lock')!
	refused = false
	fresh.state() or { refused = err.msg().contains('unavailable') }
	assert refused
	refused = false
	repository_status(fresh_root) or { refused = err.msg().contains('unavailable') }
	assert refused
	refused = false
	(Service{ root: 'relative' }).state() or { refused = err.msg().contains('absolute') }
	assert refused
}

fn test_service_refuses_ambiguous_configuration_before_mutating_package_state() {
	work, service, config := service_fixture('configuration-schema')!
	defer { os.rmdir_all(work) or {} }
	directory := state_directory(service.root)
	path := service.root + '/etc/vinix-packages/config.json'
	service.transact('install', ['app'], TransactionOptions{})!
	service.transact('remove', ['app'], TransactionOptions{})!
	mut review := service.review('install', ['app'])!
	defer { review.close() }
	original := json2.encode(config)
	retained := ['catalog.json', 'trust-history.json', 'generations/1/state.json', 'generations/2/state.json']
	mut snapshots := []string{}
	for file in retained { snapshots << os.read_file(directory + '/' + file)! }
	objects := os.ls(directory + '/objects')!
	os.mkdir_all(directory + '/generations/.stage-sentinel')!
	os.write_file(directory + '/generations/.stage-sentinel/keep', 'retained recovery data')!
	for invalid in [original.replace('"permissions":', '"permissons":'),
		original.replace('"allowed":[]', '"allowed":null'),
		original.replace('"offline":false', '"offline":true,"off\\u006cine":false'),
		original.replace('"url":', '"url":"https://example.invalid","url":')] {
		assert invalid != original
		os.write_file(path, invalid)!
		mut errors := []string{}
		service.refresh() or { errors << err.msg() }
		service.transact('install', ['app'], TransactionOptions{expected_review: review.fingerprint}) or { errors << err.msg() }
		service.rollback('') or { errors << err.msg() }
		service.collect() or { errors << err.msg() }
		service.state() or { errors << err.msg() }
		service.review('install', ['app']) or { errors << err.msg() }
		service.mirror(work + '/invalid-mirror', ['app']) or { errors << err.msg() }
		revoke_repository(service.root, 'fixture') or { errors << err.msg() }
		assert errors.len == 8 && errors.all(it.contains('invalid package configuration:')), errors.str()
		assert os.read_file(path)! == invalid && os.readlink(directory + '/current')! == 'generations/2'
		for i, file in retained { assert os.read_file(directory + '/' + file)! == snapshots[i] }
		assert os.ls(directory + '/objects')! == objects
		assert os.read_file(directory + '/generations/.stage-sentinel/keep')! == 'retained recovery data'
		assert !os.exists(work + '/invalid-mirror') && !os.exists(directory + '/generations/3')
	}
	os.write_file(path, original)!
	assert service.state()!.generation == 2 && service.state()!.previous == 1
	assert service.verify()!.packages.len == 0
	assert service.transact('install', ['app'], TransactionOptions{expected_review: review.fingerprint})!.generation == 3
	assert service.verify()!.packages.len == 1
	assert service.rollback('')!.generation == 2
}

fn test_service_history_refusal_preserves_state_payloads_and_recovery_stages() {
	work, service, config := service_fixture('history-schema')!
	defer { os.rmdir_all(work) or {} }
	directory := state_directory(service.root)
	service.transact('install', ['app'], TransactionOptions{})!
	service.transact('remove', ['app'], TransactionOptions{})!
	mut review := service.review('install', ['app'])!
	defer { review.close() }
	path := directory + '/trust-history.json'
	original := os.read_file(path)!
	mut retained := ['catalog.json', 'generations/1/state.json', 'generations/2/state.json']
	for file in os.ls(directory + '/objects')! { retained << 'objects/' + file }
	mut hashes := []string{}
	for file in retained { hashes << hash_file(directory + '/' + file)! }
	configuration := os.read_file(service.root + '/etc/vinix-packages/config.json')!
	os.mkdir_all(directory + '/generations/.stage-history-sentinel')!
	for invalid in ['null', '{"format":1}', '{"format":1,"repositories":null}',
		original.replace('"sequence":1', '"sequence":0,"sequ\\u0065nce":1')] {
		os.write_file(path, invalid)!
		mut errors := []string{}
		service.refresh() or { errors << err.msg() }
		service.transact('install', ['app'], TransactionOptions{expected_review: review.fingerprint}) or { errors << err.msg() }
		service.review('install', ['app']) or { errors << err.msg() }
		service.mirror(work + '/invalid-history-mirror', ['app']) or { errors << err.msg() }
		review_repository(service.root, 'enroll', config.repositories[0], true) or { errors << err.msg() }
		enroll_repository(service.root, config.repositories[0], true) or { errors << err.msg() }
		assert errors.len == 6 && errors.all(it.contains('invalid repository trust history:')), errors.str()
		assert os.read_file(path)! == invalid && service.state()!.generation == 2
		assert os.read_file(service.root + '/etc/vinix-packages/config.json')! == configuration
		for i, file in retained { assert hash_file(directory + '/' + file)! == hashes[i] }
		assert os.is_dir(directory + '/generations/.stage-history-sentinel')
		assert !os.exists(directory + '/refresh') && !os.exists(directory + '/enrollment')
		assert !os.exists(directory + '/generations/3') && !os.exists(work + '/invalid-history-mirror')
	}
	os.write_file(path, original)!
	assert service.transact('install', ['app'], TransactionOptions{expected_review: review.fingerprint})!.generation == 3
	assert service.verify()!.packages.len == 1 && service.rollback('')!.generation == 2
}
