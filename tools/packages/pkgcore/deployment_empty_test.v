// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

fn empty_deployment_fixture(architecture string) !(string, Service, Config) {
	work := os.temp_dir() + '/vinix-empty-deployment-' + architecture + '-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/root/etc/vinix-packages')!
	os.mkdir_all(work + '/source/bin')!
	os.write_file(work + '/source/bin/runner', 'signed fixture runner\n')!
	os.chmod(work + '/source/bin/runner', 0o755)!
	key := keygen(work + '/seed')!
	config := Config{ architecture: architecture,
		repositories: [Repository{ id: 'fixture', url: 'file://' + work + '/repository', public_key: key }],
		policy: Policy{ offline: true, reserve_bytes: 0, licenses: ['Fixture-EULA'], allow_firmware: true } }
	os.write_file(work + '/root/etc/vinix-packages/config.json', json2.encode(config))!
	for p in [
		Package{ id: 'app', version: '1.0.0', architecture: architecture, name: 'Application', description: 'Removal fixture',
			license: 'Fixture-EULA', proprietary: true, kind: 'linux', runtime: 'runtime', entrypoint: 'bin/runner',
			permissions: ['files'], associations: ['text/plain'], dependencies: [Dependency{ id: 'runtime' }] },
		Package{ id: 'runtime', version: '1.0.0', architecture: architecture, name: 'Runtime', license: 'MIT',
			kind: 'runtime', permissions: ['process'], dependencies: [Dependency{ id: 'assets' }] },
		Package{ id: 'assets', version: '1.0.0', architecture: 'all', name: 'Firmware fixture', license: 'MIT', kind: 'data', firmware: true },
	] {
		os.write_file(work + '/manifest.json', json2.encode(p))!
		pack(work + '/manifest.json', work + '/source', work + '/repository')!
	}
	publish(work + '/repository', 'fixture', work + '/seed', 1, time.now().unix() + 3600)!
	service := Service{ root: work + '/root' }
	service.refresh()!
	service.transact('install', ['app'], TransactionOptions{})!
	return work, service, config
}

fn empty_deployment_text(format int, architecture string) string {
	return '{"format":${format},"architecture":"${architecture}","packages":[]' + if format == 2 { ',"locked":[]}' } else { '}' }
}

fn test_empty_deployment_removes_installed_closure_with_damaged_offline_catalog() {
	for architecture in ['aarch64', 'x86_64']! {
		for format in [1, 2]! {
			work, service, config := empty_deployment_fixture(architecture)!
			defer { os.rmdir_all(work) or {} }
			store := state_directory(service.root)
			catalog := os.read_file(store + '/catalog.json')!
			history := os.read_file(store + '/trust-history.json')!
			before := service.state()!
			active := os.readlink(store + '/current')!
			state_bytes := os.read_file(store + '/current/state.json')!
			assert before.requested == ['app'] && before.packages.len == 3
			assert os.ls(store + '/current/share/applications')!.len == 1
			data := service.root + '/home/alex/.local/share/vinix-apps/app'
			os.mkdir_all(data)!
			os.write_file(data + '/saved', 'retain personal application data')!
			os.rmdir_all(work + '/repository')!
			for object in os.ls(store + '/objects')! { os.rm(store + '/objects/' + object)! }
			blocked := Config{ ...config, repositories: if format == 2 { []Repository{} } else { config.repositories },
				policy: Policy{ offline: true, allowed: ['other'], permissions: [], licenses: [], allow_firmware: false,
					pins: [Dependency{ id: 'app', minimum: '9.0.0' }], reserve_bytes: 1234 } }
			blocked_text := json2.encode(blocked)
			os.write_file(service.root + '/etc/vinix-packages/config.json', blocked_text)!
			os.write_file(store + '/catalog.json', '{damaged catalog')!
			os.write_file(store + '/trust-history.json', '{damaged history')!
			path := work + '/empty.json'
			os.write_file(path, empty_deployment_text(format, architecture))!
			// Removal also works if active payloads are damaged; its historical
			// metadata still supplies complete review disclosures and rollback ID.
			payload := store + '/current/apps/app/bin/runner'
			original := os.read_file(payload)!
			os.write_file(payload, 'damaged removed file')!
			mut review := service.review_deployment(path)!
			defer { review.close() }
			assert review.rows.len == 3 && review.rows.all(it.action == 'remove')
			assert review.rows.map(it.id) == ['app', 'assets', 'runtime']
			assert review.rows[0].proprietary && review.rows[0].license == 'Fixture-EULA' && review.rows[0].permissions == ['files']
			assert review.rows[1].firmware && review.rows[2].permissions == ['process']
			assert review.rows.all(it.repository == 'fixture' && it.public_key == config.repositories[0].public_key)
			assert review.disk_needed == 4 * 1024 * 1024 && review.disk_reserve == 1234
			assert os.readlink(store + '/current')! == active && os.read_file(store + '/current/state.json')! == state_bytes
			// Catalog and replay history do not participate in an empty target.
			os.rm(store + '/catalog.json')!; os.rm(store + '/trust-history.json')!
			mut absent := service.review_deployment(path)!
			assert absent.fingerprint == review.fingerprint
			absent.close()
			removed := service.apply_deployment(path, review.fingerprint)!
			assert removed.generation == 2 && removed.previous == 1 && removed.packages.len == 0 && removed.requested.len == 0
			assert service.verify()! == removed && os.ls(store + '/current/apps')!.len == 0
			assert os.ls(store + '/current/share/applications')!.len == 0
			assert os.read_file(data + '/saved')! == 'retain personal application data'
			assert os.read_file(store + '/' + active + '/state.json')! == state_bytes
			assert os.read_file(service.root + '/etc/vinix-packages/config.json')! == blocked_text
			assert !os.exists(store + '/catalog.json') && !os.exists(store + '/trust-history.json')
			assert os.ls(store + '/objects')!.len == 0
			mut refused := false
			service.apply_deployment(path, review.fingerprint) or { refused = err.msg().contains('stale') }
			assert refused && service.state()! == removed
			mut noop := service.review_deployment(path)!
			assert noop.rows.len == 0 && noop.disk_needed == 0
			assert service.apply_deployment(path, noop.fingerprint)! == removed && service.deploy(path)! == removed
			noop.close()
			// Rollback still requires trusted/policy-admitted metadata and an
			// intact retained tree; empty deployment grants no restore approval.
			refused = false
			service.review('rollback', []) or { refused = true }
			assert refused && service.state()! == removed
			os.write_file(service.root + '/etc/vinix-packages/config.json', json2.encode(config))!
			os.write_file(store + '/catalog.json', catalog)!; os.write_file(store + '/trust-history.json', history)!
			refused = false
			service.review('rollback', []) or { refused = true }
			assert refused && service.state()! == removed
			os.write_file(store + '/' + active + '/apps/app/bin/runner', original)!
			mut rollback := service.review('rollback', [])!
			assert service.rollback(rollback.fingerprint)!.packages == before.packages
			rollback.close()
			assert service.verify()!.requested == before.requested && os.ls(store + '/objects')!.len == 0
		}
	}
	println('Empty deployment: formats 1/2 both architectures offline/revoked/damaged/absent catalog remove complete closure, disclose policy, retain data and enforce rollback admission PASS')
}

fn test_empty_deployment_preserves_review_lock_state_and_transaction_recovery_checks() {
	work, service, config := empty_deployment_fixture('aarch64')!
	defer { os.rmdir_all(work) or {} }
	store := state_directory(service.root)
	before := service.state()!
	state_bytes := os.read_file(store + '/current/state.json')!
	path := work + '/empty.json'
	empty := empty_deployment_text(2, config.architecture)
	os.write_file(path, empty)!
	mut pinned := service.snapshot_deployment([])!
	// Surplus pins in an empty-root document must refuse, even offline.
	os.write_file(store + '/catalog.json', '{damaged catalog')!
	os.write_file(store + '/trust-history.json', '{damaged history')!
	os.write_file(path, json2.encode(DeploymentLock{ architecture: config.architecture, locked: pinned.locked }))!
	mut refused := false
	service.review_deployment(path) or { refused = err.msg().contains('outside the requested dependency closure') }
	assert refused
	os.write_file(path, json2.encode(pinned))!
	refused = false
	service.review_deployment(path) or { refused = err.msg().contains('invalid cached repository metadata') }
	assert refused // a nonempty target must still authenticate catalog metadata
	pinned.close()
	os.write_file(path, empty)!
	mut review := service.review_deployment(path)!
	defer { review.close() }
	mut generic := service.review('deploy', [])!
	defer { generic.close() }
	assert generic.rows == review.rows && generic.fingerprint != review.fingerprint
	assert service.plan('deploy', [])!.packages.len == 0
	sentinel := store + '/generations/.stage-empty-sentinel'
	os.mkdir(sentinel)!
	os.write_file(sentinel + '/keep', 'preserve abandoned recovery evidence')!
	for fingerprint in ['0'.repeat(64), generic.fingerprint] {
		refused = false
		service.apply_deployment(path, fingerprint) or { refused = err.msg().contains('stale') }
		assert refused
	}
	refused = false
	service.transact('deploy', [], TransactionOptions{ expected_review: review.fingerprint }) or { refused = err.msg().contains('stale') }
	assert refused
	os.write_file(service.root + '/etc/vinix-packages/config.json', json2.encode(Config{ ...config, policy: Policy{ reserve_bytes: 1234 } }))!
	refused = false
	service.apply_deployment(path, review.fingerprint) or { refused = err.msg().contains('stale') }
	assert refused
	os.write_file(service.root + '/etc/vinix-packages/config.json', json2.encode(config))!
	// A valid empty document cannot hide an incoherent installed state.
	os.write_file(store + '/current/state.json', '{damaged installed state')!
	refused = false
	service.apply_deployment(path, review.fingerprint) or { refused = true }
	assert refused
	os.write_file(store + '/current/state.json', state_bytes)!
	guard := acquire(store)!
	os.write_file(service.root + '/etc/vinix-packages/config.json', '{damaged config')!
	refused = false
	service.review_deployment(path) or { refused = err.msg().contains('another package transaction') }
	assert refused
	guard.release()
	refused = false
	service.apply_deployment(path, review.fingerprint) or { refused = err.msg().contains('invalid package configuration') }
	assert refused
	os.write_file(service.root + '/etc/vinix-packages/config.json', json2.encode(config))!
	assert service.state()! == before && os.read_file(sentinel + '/keep')! == 'preserve abandoned recovery evidence'
	os.rmdir_all(sentinel)!
	refused = false
	service.transact('deploy', [], TransactionOptions{ expected_review: generic.fingerprint, stop_before_activation: true }) or { refused = err.msg().contains('fixture interrupted before activation') }
	assert refused && service.state()! == before
	assert os.ls(store + '/generations')!.any(it.starts_with('.stage-'))
	assert service.apply_deployment(path, review.fingerprint)!.packages.len == 0
	assert os.ls(store + '/generations')!.all(!it.starts_with('.stage-'))
	println('Empty deployment: nonempty/surplus lock refusal, generic/file review domains, stale config, invalid state, busy lock and interrupted-stage recovery PASS')
}

fn test_empty_deployment_on_fresh_store_is_noop_but_configuration_is_validated() {
	work := os.temp_dir() + '/vinix-empty-fresh-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	defer { os.rmdir_all(work) or {} }
	os.mkdir_all(work + '/etc/vinix-packages')!
	config := Config{ architecture: 'x86_64', repositories: [Repository{ id: 'absent',
		url: 'file://' + work + '/unavailable', public_key: 'a'.repeat(64) }], policy: Policy{ offline: true } }
	os.write_file(work + '/etc/vinix-packages/config.json', json2.encode(config))!
	service := Service{ root: work }
	path := work + '/empty.json'
	os.write_file(path, empty_deployment_text(2, config.architecture))!
	mut unavailable := false
	service.review_deployment(path) or { unavailable = err.msg().contains('package state is unavailable') }
	assert unavailable && !os.exists(state_directory(work))
	// Writers initialize coordination directories; public readers never do.
	assert service.transact('deploy', [], TransactionOptions{})!.generation == 0
	for format in [1, 2]! {
		os.write_file(path, empty_deployment_text(format, config.architecture))!
		mut review := service.review_deployment(path)!
		assert review.rows.len == 0 && review.disk_needed == 0
		assert service.apply_deployment(path, review.fingerprint)!.generation == 0
		review.close()
	}
	assert !os.exists(state_directory(work) + '/current') && os.ls(state_directory(work) + '/generations')!.len == 0
	mut refused := false
	operation_plan(Config{ architecture: 'invalid' }, state_directory(work), State{}, 'deploy', []) or { refused = true }
	assert refused
	refused = false
	service.review('remove', []) or { refused = true }
	assert refused
	println('Empty deployment: initialized fresh store no activation or acquisition; invalid configuration and empty remove still refuse PASS')
}
