// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

fn deployment_fixture(label string) !(string, Service, Config) {
	work := os.temp_dir() + '/vinix-deployment-' + label + '-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/root/etc/vinix-packages')!
	os.mkdir_all(work + '/source/bin')!
	os.write_file(work + '/source/bin/runner', 'signed runner\n')!
	os.chmod(work + '/source/bin/runner', 0o755)!
	key := keygen(work + '/seed')!
	config := Config{ architecture: 'aarch64',
		repositories: [Repository{ id: 'fixture', url: 'file://' + work + '/repository', public_key: key }],
		policy: Policy{ reserve_bytes: 0 } }
	os.write_file(work + '/root/etc/vinix-packages/config.json', json2.encode(config))!
	deployment_version(work, '1.0.0')!
	os.write_file(work + '/manifest.json', json2.encode(Package{ id: 'unused', version: '1.0.0',
		architecture: 'all', name: 'Data', license: 'MIT', kind: 'data' }))!
	pack(work + '/manifest.json', work + '/source', work + '/repository')!
	publish(work + '/repository', 'fixture', work + '/seed', 1, time.now().unix() + 3600)!
	service := Service{ root: work + '/root' }
	service.refresh()!
	return work, service, config
}

fn deployment_version(work string, version string) ! {
	for p in [
		Package{ id: 'app', version: version, architecture: 'aarch64', name: 'Application', license: 'MIT',
			kind: 'linux', runtime: 'runtime', entrypoint: 'bin/runner', permissions: ['files'],
			dependencies: [Dependency{ id: 'runtime', minimum: version }] },
		Package{ id: 'runtime', version: version, architecture: 'aarch64', name: 'Runtime', license: 'MIT',
			kind: 'runtime', permissions: ['process'] },
	] {
		os.write_file(work + '/manifest.json', json2.encode(p))!
		pack(work + '/manifest.json', work + '/source', work + '/repository')!
	}
}

fn write_deployment(work string, document DeploymentLock) !string {
	path := work + '/deployment.json'
	os.write_file(path, json2.encode(document))!
	return path
}

fn test_locked_deployments_reproduce_versions_and_runtime_closure_after_refresh_and_offline() {
	work, service, config := deployment_fixture('reproducible')!
	defer { os.rmdir_all(work) or {} }
	locked := service.lock_deployment(['app'])!
	assert locked.format == 2 && locked.packages == ['app'] && locked.locked.map(it.id) == ['app', 'runtime']
	assert locked.locked.all(it.version == '1.0.0' && it.minimum_sequence == 1 && digest_valid(it.metadata_sha256))
	path := write_deployment(work, locked)!
	mut review := service.review_deployment(path)!
	assert review.rows.len == 2 && review.rows.all(it.action == 'install') && review.rows[1].permissions == ['process']
	assert service.state()!.generation == 0 && os.ls(state_directory(service.root) + '/objects')!.len == 0
	service.apply_deployment(path, review.fingerprint)!
	review.close()
	assert service.lock_deployment([])!.locked == locked.locked
	deployment_version(work, '2.0.0')!
	publish(work + '/repository', 'fixture', work + '/seed', 2, time.now().unix() + 3600)!
	service.refresh()!
	service.transact('upgrade', [], TransactionOptions{})!
	assert service.state()!.packages.all(it.package.version == '2.0.0')
	mut downgrade := service.review_deployment(path)!
	assert downgrade.rows.all(it.action == 'update' && it.installed_version == '2.0.0' && it.version == '1.0.0')
	service.apply_deployment(path, downgrade.fingerprint)!
	downgrade.close()
	assert service.verify()!.packages.all(it.package.version == '1.0.0' && it.sequence == 2)
	// A relocated offline mirror retains the publisher and exact manifests.
	service.mirror(work + '/mirror', ['app'])!
	root := work + '/offline'
	os.mkdir_all(root + '/etc/vinix-packages')!
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(Config{ ...config,
		repositories: [Repository{ ...config.repositories[0], url: 'file://' + work + '/mirror/fixture' }],
		policy: Policy{ offline: true, reserve_bytes: 0 } }))!
	offline := Service{ root: root }
	offline.refresh()!
	mut offline_review := offline.review_deployment(path)!
	offline.apply_deployment(path, offline_review.fingerprint)!
	offline_review.close()
	assert offline.verify()!.packages == service.state()!.packages
	// Idempotent apply avoids another generation; explicit empty roots uninstall.
	mut unchanged := offline.review_deployment(path)!
	assert unchanged.disk_needed == 0 && unchanged.rows.all(it.action == 'keep')
	assert offline.apply_deployment(path, unchanged.fingerprint)!.generation == 1
	unchanged.close()
	write_deployment(work, DeploymentLock{ architecture: 'aarch64' })!
	assert offline.deploy(path)!.packages.len == 0
	assert offline.rollback('')!.packages.all(it.package.version == '1.0.0')
}

fn test_deployment_reviews_bind_document_policy_state_and_command_domain_before_side_effects() {
	work, service, config := deployment_fixture('freshness')!
	defer { os.rmdir_all(work) or {} }
	locked := service.lock_deployment(['app'])!
	path := write_deployment(work, locked)!
	directory := state_directory(service.root)
	os.mkdir_all(directory + '/generations/.stage-sentinel')!
	mut review := service.review_deployment(path)!
	defer { review.close() }
	// Insignificant ordering/whitespace is canonical, including format-1 roots.
	os.write_file(path, json2.encode(DeploymentLock{ ...locked, locked: [locked.locked[1], locked.locked[0]] }) + '\n')!
	mut reordered := service.review_deployment(path)!
	assert reordered.fingerprint == review.fingerprint
	reordered.close()
	mut ordinary := service.review('deploy', ['app'])!
	assert ordinary.fingerprint != review.fingerprint
	mut refused := false
	service.apply_deployment(path, ordinary.fingerprint) or { refused = err.msg().contains('stale') }
	assert refused
	refused = false
	service.transact('deploy', ['app'], TransactionOptions{ expected_review: review.fingerprint }) or { refused = err.msg().contains('stale') }
	assert refused
	// Even when resolution is identical, changing from a lock to roots invalidates review.
	os.write_file(path, '{"format":1,"architecture":"aarch64","packages":["app"]}')!
	refused = false
	service.apply_deployment(path, review.fingerprint) or { refused = err.msg().contains('stale') }
	assert refused
	write_deployment(work, locked)!
	save_configuration(service.root + '/etc/vinix-packages/config.json', Config{ ...config,
		policy: Policy{ ...config.policy, reserve_bytes: 1 } })!
	refused = false
	service.apply_deployment(path, review.fingerprint) or { refused = err.msg().contains('stale') }
	assert refused && service.state()!.generation == 0
	assert os.ls(directory + '/objects')!.len == 0 && os.is_dir(directory + '/generations/.stage-sentinel')
	save_configuration(service.root + '/etc/vinix-packages/config.json', config)!
	service.transact('install', ['unused'], TransactionOptions{})!
	refused = false
	service.apply_deployment(path, review.fingerprint) or { refused = err.msg().contains('stale') }
	assert refused && service.state()!.requested == ['unused']
	mut fresh := service.review_deployment(path)!
	assert fresh.rows.any(it.id == 'unused' && it.action == 'remove')
	service.apply_deployment(path, fresh.fingerprint)!
	fresh.close()
	assert service.state()!.requested == ['app']
}

fn test_deployment_lock_refuses_metadata_substitution_missing_or_extra_closure_and_policy() {
	work, service, config := deployment_fixture('closure')!
	defer { os.rmdir_all(work) or {} }
	locked := service.lock_deployment(['app'])!
	extra := service.lock_deployment(['unused'])!.locked[0]
	for pins in [
		[locked.locked[0]],
		[locked.locked[0], locked.locked[1], extra],
		[DeploymentPackage{ ...locked.locked[0], metadata_sha256: '0'.repeat(64) }, locked.locked[1]],
		[DeploymentPackage{ ...locked.locked[0], minimum_sequence: 2 }, locked.locked[1]],
		[DeploymentPackage{ ...locked.locked[0], public_key: '0'.repeat(64) }, locked.locked[1]],
	] {
		path := write_deployment(work, DeploymentLock{ ...locked, locked: pins })!
		mut refused := false
		service.deploy(path) or { refused = true }
		assert refused && service.state()!.generation == 0
		assert os.ls(state_directory(service.root) + '/objects')!.len == 0
	}
	path := write_deployment(work, locked)!
	// All dependency permissions and version pins still require organization approval.
	for policy in [Policy{ permissions: ['files'], reserve_bytes: 0 },
		Policy{ pins: [Dependency{ id: 'runtime', minimum: '2.0.0' }], reserve_bytes: 0 },
		Policy{ allowed: ['app'], reserve_bytes: 0 }] {
		save_configuration(service.root + '/etc/vinix-packages/config.json', Config{ ...config, policy: policy })!
		mut refused := false
		service.review_deployment(path) or { refused = true }
		assert refused && service.state()!.generation == 0
	}
	save_configuration(service.root + '/etc/vinix-packages/config.json', config)!
	// The same ID/version from the same trusted publisher cannot alter launch metadata.
	actual := os.ls(work + '/repository/manifests')!.filter(it.contains('app'))[0]
	p := json2.decode[Package](os.read_file(work + '/repository/manifests/' + actual)!)!
	os.write_file(work + '/repository/manifests/' + actual, json2.encode(Package{ ...p, arguments: ['changed'] }))!
	publish(work + '/repository', 'fixture', work + '/seed', 2, time.now().unix() + 3600)!
	service.refresh()!
	mut refused := false
	service.review_deployment(path) or { refused = err.msg().contains('metadata changed') }
	assert refused
}

fn test_deployment_documents_are_strict_bounded_and_lock_before_reading() {
	work, service, _ := deployment_fixture('strict')!
	defer { os.rmdir_all(work) or {} }
	locked := service.lock_deployment(['app'])!
	valid := json2.encode(locked)
	path := work + '/deployment.json'
	for invalid in [
		valid.replace('"format":2', '"format":3'), valid.replace('"format":2,', ''),
		valid.replace('"format":2', '"format":"2"'), valid.replace('"packages":["app"]', '"packages":null'),
		valid.replace('"locked":[', '"unknown":[ '), valid.replace('"minimum_sequence":1', '"minimum_sequence":null'),
		valid.replace('"minimum_sequence":1', '"minimum_sequence":-1'), valid.replace('"minimum_sequence":1', '"minimum_sequence":"1"'),
		valid.replace('"minimum_sequence":1', '"minimum_sequence":18446744073709551616'),
		valid.replace('"minimum_sequence":1,', ''), valid.replace('"version":"1.0.0"', '"version":"01.0.0"'),
		valid.replace('"format":2', '"format":2,"format":2'),
		valid.replace('"id":"app"', '"id":"app","i\\u0064":"app"'),
		valid.replace('"id":"app"', '"id":"app","extra":true'),
		'{"format":1,"architecture":"aarch64"}', '{"format":1,"architecture":"aarch64","packages":["app","app"]}',
		'{"format":1,"architecture":"aarch64","packages":[],"locked":[]}',
		json2.encode(DeploymentLock{ ...locked, architecture: 'x86_64' }),
		json2.encode(DeploymentLock{ ...locked, locked: [locked.locked[0], locked.locked[0]] }),
		json2.encode(DeploymentLock{ ...locked, packages: ['app'].repeat(4097) }),
	] {
		os.write_file(path, invalid)!
		mut refused := false
		service.deploy(path) or { refused = true }
		assert refused, invalid
	}
	write_deployment(work, locked)!
	os.symlink(path, work + '/linked.json')!
	mut refused := false
	service.review_deployment(work + '/linked.json') or { refused = err.msg().contains('regular file') }
	assert refused
	guard := acquire(state_directory(service.root))!
	os.write_file(service.root + '/etc/vinix-packages/config.json', '{broken')!
	mut messages := []string{}
	service.lock_deployment(['app']) or { messages << err.msg() }
	service.review_deployment(work + '/absent') or { messages << err.msg() }
	service.apply_deployment(work + '/absent', '0'.repeat(64)) or { messages << err.msg() }
	guard.release()
	assert messages.len == 3 && messages.all(it.contains('another package transaction'))
}

fn test_package_metadata_digest_is_canonical_and_binds_payloads_permissions_and_runtime() {
	work, service, _ := deployment_fixture('digest')!
	defer { os.rmdir_all(work) or {} }
	p := service.plan('deploy', ['app'])!.packages[0].package
	base := Package{ ...p, permissions: ['files', 'network'], associations: ['text/plain', 'image/png'],
		dependencies: [Dependency{ id: 'runtime' }, Dependency{ id: 'unused' }] }
	assert package_metadata_digest(base)! == package_metadata_digest(Package{ ...base,
		permissions: ['network', 'files'], associations: ['image/png', 'text/plain'],
		dependencies: [base.dependencies[1], base.dependencies[0]] })!
	for changed in [Package{ ...base, permissions: ['files'] }, Package{ ...base, arguments: ['--changed'] },
		Package{ ...base, license: 'Vendor-EULA', proprietary: true }, Package{ ...base, entrypoint: 'bin/other' },
		Package{ ...base, files: [Payload{ ...base.files[0], sha256: '0'.repeat(64) }] }] {
		assert package_metadata_digest(changed)! != package_metadata_digest(base)!
	}
}
