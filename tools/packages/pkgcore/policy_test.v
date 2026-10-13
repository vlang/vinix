// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

fn policy_fixture(label string, installed bool) !(string, Service, Config) {
	work := os.temp_dir() + '/vinix-policy-' + label + '-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	root := work + '/root'
	os.mkdir_all(root + '/etc/vinix-packages')!
	key := keygen(work + '/seed')!
	config := Config{ architecture: 'aarch64', launch_user: 'alex',
		repositories: [Repository{ id: 'fixture', url: 'file://' + work + '/repository', public_key: key }]
		policy: Policy{ licenses: ['Vendor-EULA'], allow_firmware: true, reserve_bytes: 0 } }
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(config))!
	service := Service{ root: root }
	if installed {
		os.mkdir_all(work + '/source/bin')!
		os.write_file(work + '/source/bin/runner', 'signed fixture\n')!
		os.chmod(work + '/source/bin/runner', 0o755)!
		for package in [
			Package{ id: 'app', name: 'Application', version: '1.0.0', architecture: 'aarch64', license: 'MIT',
				kind: 'linux', runtime: 'runtime', entrypoint: 'bin/runner', dependencies: [Dependency{ id: 'runtime' }] },
			Package{ id: 'runtime', name: 'Runtime', version: '1.0.0', architecture: 'aarch64', license: 'Vendor-EULA',
				kind: 'runtime', proprietary: true, firmware: true, permissions: ['process'], dependencies: [Dependency{ id: 'app' }] },
		] {
			os.write_file(work + '/manifest.json', json2.encode(package))!
			pack(work + '/manifest.json', work + '/source', work + '/repository')!
		}
		publish(work + '/repository', 'fixture', work + '/seed', 1, time.now().unix() + 3600)!
		service.refresh()!
		service.transact('install', ['app'], TransactionOptions{})!
	}
	return work, service, config
}

fn policy_file(work string, policy Policy) !string {
	path := work + '/policy.json'
	os.write_file(path, json2.encode(PolicyDocument{ architecture: 'aarch64', policy: policy }))!
	return path
}

fn test_policy_review_is_read_only_canonical_and_reports_dependency_effects() {
	work, service, config := policy_fixture('impact', true)!
	defer { os.rmdir_all(work) or {} }
	directory := state_directory(service.root)
	before_config := os.read_file(service.root + '/etc/vinix-packages/config.json')!
	before_state := service.state()!
	before_history := os.read_file(directory + '/trust-history.json')!
	path := policy_file(work, Policy{ allowed: ['runtime', 'app'], permissions: [], reserve_bytes: 0 })!
	mut review := service.review_policy(path)!
	defer { review.close() }
	assert review.rows.map(it.id) == ['app', 'runtime']
	assert review.rows.all(it.diagnostic_before == '' && it.diagnostic_after.contains('runtime: permissions blocked'))
	assert review.rows[1].proprietary && review.rows[1].firmware && !review.rows[1].requested
	assert review.proposed.allowed == ['app', 'runtime'] && review.previous.licenses == ['Vendor-EULA']
	assert os.read_file(service.root + '/etc/vinix-packages/config.json')! == before_config
	assert service.state()! == before_state && os.read_file(directory + '/trust-history.json')! == before_history
	os.write_file(path, json2.encode(PolicyDocument{ architecture: 'aarch64', policy: Policy{ ...review.proposed, allowed: ['app', 'runtime'] } }))!
	mut reordered := service.review_policy(path)!
	assert reordered.fingerprint == review.fingerprint
	reordered.close()
	mut applied := service.apply_policy(path, review.fingerprint)!
	applied.close()
	after := load_config(service.root)!
	assert after.repositories == config.repositories && after.launch_user == config.launch_user && after.architecture == config.architecture
	assert after.policy.permissions.len == 0 && after.policy.allowed == ['app', 'runtime']
	assert service.state()! == before_state && os.read_file(directory + '/trust-history.json')! == before_history
	mut stale := false
	service.apply_policy(path, review.fingerprint) or { stale = err.msg().contains('stale') }
	assert stale
	// License and firmware denial also propagate from the implicit runtime.
	for policy in [Policy{ permissions: ['process'], reserve_bytes: 0 },
		Policy{ permissions: ['process'], licenses: ['Vendor-EULA'], reserve_bytes: 0 }] {
		policy_file(work, policy)!
		mut changed := service.review_policy(path)!
		assert changed.rows.all(it.diagnostic_after.contains(if policy.licenses.len == 0 { 'accept license' } else { 'firmware installation' }))
		changed.close()
	}
	// Accepting the exact license and allowing firmware are separate, explicit
	// reviewed settings. Restoring both makes the same runtime/app closure usable.
	policy_file(work, config.policy)!
	mut acceptance := service.review_policy(path)!
	assert acceptance.rows.all(it.diagnostic_after == '')
	mut accepted := service.apply_policy(path, acceptance.fingerprint)!
	assert accepted.policy.allow_firmware && accepted.policy.licenses == ['Vendor-EULA']
	accepted.close()
	acceptance.close()
	policy_file(work, review.proposed)!
	mut tightened := service.review_policy(path)!
	mut restricted := service.apply_policy(path, tightened.fingerprint)!
	restricted.close()
	tightened.close()
	// Tightened policy never prevents explicit uninstall.
	service.transact('remove', ['app'], TransactionOptions{})!
	assert service.state()!.packages.len == 0
}

fn test_policy_apply_binds_configuration_state_and_proposed_document() {
	work, service, config := policy_fixture('stale', true)!
	defer { os.rmdir_all(work) or {} }
	path := policy_file(work, Policy{ reserve_bytes: 1234 })!
	mut review := service.review_policy(path)!
	defer { review.close() }
	policy_file(work, Policy{ reserve_bytes: 1235 })!
	mut stale := false
	service.apply_policy(path, review.fingerprint) or { stale = err.msg().contains('stale') }
	assert stale && load_config(service.root)!.policy == config.policy
	policy_file(work, review.proposed)!
	revoke_repository(service.root, 'fixture')!
	stale = false
	service.apply_policy(path, review.fingerprint) or { stale = err.msg().contains('stale') }
	assert stale && load_config(service.root)!.repositories.len == 0
	save_configuration(service.root + '/etc/vinix-packages/config.json', config)!
	service.transact('remove', ['app'], TransactionOptions{})!
	stale = false
	service.apply_policy(path, review.fingerprint) or { stale = err.msg().contains('stale') }
	assert stale && service.state()!.packages.len == 0
	mut fresh := service.review_policy(path)!
	mut result := service.apply_policy(path, fresh.fingerprint)!
	assert result.policy.reserve_bytes == 1234
	result.close()
	fresh.close()
}

fn test_policy_documents_are_complete_bounded_and_explicit_on_fresh_images() {
	work, service, config := policy_fixture('validation', false)!
	defer { os.rmdir_all(work) or {} }
	path := policy_file(work, config.policy)!
	mut document := service.policy()!
	assert document.policy == canonical_policy(config.policy)!
	document.close()
	mut review := service.review_policy(path)!
	assert review.generation == 0 && review.rows.len == 0 && !os.exists(state_directory(service.root))
	mut decoded := decode_policy_review(json2.encode(review))!
	decoded.close()
	assert decoded.fingerprint == '' && decoded.rows.len == 0 && decoded.proposed.permissions.len == 0
	if _ := decode_policy_review(json2.encode(review).replace('"offline":false,', '')) { assert false }
	review.close()
	valid := os.read_file(path)!
	for invalid in [valid.replace('"format":1', '"format":2'), valid.replace('aarch64', 'x86_64'),
		valid.replace('"offline":false,', ''), valid.replace('"offline":false', '"offline":null'),
		valid.replace('"offline":false', '"offline":"false"'), valid.replace('"permissions":["network","files","process","display","audio"]', '"permissions":null'),
		valid.replace('"reserve_bytes":0', '"reserve_bytes":-1'), valid.replace('"reserve_bytes":0', '"reserve_bytes":"0"'),
		valid.replace('"reserve_bytes":0', '"reserve_bytes":18446744073709551616')] {
		os.write_file(path, invalid)!
		mut refused := false
		service.review_policy(path) or { refused = true }
		assert refused, invalid
	}
	for policy in [Policy{ allowed: ['app', 'app'] }, Policy{ pins: [Dependency{ id: 'app' }, Dependency{ id: 'app' }] },
		Policy{ permissions: ['files', 'files'] }, Policy{ licenses: ['EULA', 'EULA'] }, Policy{ licenses: ['bad\nlicense'] },
		Policy{ licenses: [''] }, Policy{ reserve_bytes: u64(1024) * 1024 * 1024 * 1024 + 1 },
		Policy{ pins: [Dependency{ id: 'app', minimum: '2.0.0', before: '1.0.0' }] }] {
		policy_file(work, policy)!
		mut refused := false
		service.review_policy(path) or { refused = true }
		assert refused
	}
	assert load_config(service.root)!.policy == config.policy && !os.exists(state_directory(service.root))
}

fn test_policy_reader_and_writer_locks_and_unsafe_configuration() {
	work, service, config := policy_fixture('locks', true)!
	defer { os.rmdir_all(work) or {} }
	path := policy_file(work, config.policy)!
	mut review := service.review_policy(path)!
	defer { review.close() }
	guard := acquire(state_directory(service.root))!
	mut messages := []string{}
	service.policy() or { messages << err.msg() }
	service.review_policy(path) or { messages << err.msg() }
	service.apply_policy(path, review.fingerprint) or { messages << err.msg() }
	guard.release()
	assert messages.len == 3 && messages.all(it.contains('another package transaction'))
	configuration := service.root + '/etc/vinix-packages/config.json'
	os.chmod(configuration, 0o666)!
	mut refused := false
	service.apply_policy(path, review.fingerprint) or { refused = err.msg().contains('administrator-owned') }
	assert refused
	os.chmod(configuration, 0o644)!
	os.symlink(path, work + '/linked-policy.json')!
	refused = false
	service.review_policy(work + '/linked-policy.json') or { refused = err.msg().contains('regular file') }
	assert refused
}

fn test_policy_documents_reject_unknown_and_duplicate_keys_before_review_or_apply() {
	work, service, config := policy_fixture('keys', true)!
	defer { os.rmdir_all(work) or {} }
	path := policy_file(work, Policy{ offline: true, allowed: ['app', 'runtime'],
		pins: [Dependency{ id: 'app', minimum: '1.0.0', before: '2.0.0' },
			Dependency{ id: 'runtime', minimum: '1.0.0' }],
		licenses: ['Vendor-EULA'], allow_firmware: true, reserve_bytes: 0 })!
	valid := os.read_file(path)!
	mut reviewed := service.review_policy(path)!
	defer { reviewed.close() }
	state := service.state()!
	history := os.read_file(state_directory(service.root) + '/trust-history.json')!
	configuration := os.read_file(service.root + '/etc/vinix-packages/config.json')!
	for invalid in [
		valid.replace('"format":1', '"format":1,"format":1'),
		valid.replace('"format":1', '"format":1,"f\\u006frmat":1'),
		valid.replace('"architecture":"aarch64"', '"architecture":"x86_64","architecture":"aarch64"'),
		valid.replace('"format":1', '"format":1,"offline":false'),
		valid.replace('"policy":{', '"policy":{"unknown":{"pins":[]},'),
		valid.replace('"offline":true', '"offline":false,"offline":true'),
		valid.replace('"offline":true', '"off\\u006cine":false,"offline":true'),
		valid.replace('"offline":true', '"offline":true,"format":1'),
		valid.replace('"allow_firmware":true', '"allow_firmware":false,"allow_firmware":true'),
		valid.replace('"licenses":["Vendor-EULA"]', '"licenses":[],"licenses":["Vendor-EULA"]'),
		valid.replace('"id":"app"', '"id":"app","id":"app"'),
		valid.replace('"minimum":"1.0.0"', '"minimum":"0.0.0","minimum":"1.0.0"'),
		valid.replace('"id":"app"', '"id":"app","permissions":["files"]'),
	] {
		os.write_file(path, invalid)!
		mut rejected := 0
		service.review_policy(path) or { assert err.msg().contains('document field'); rejected += 1 }
		service.apply_policy(path, reviewed.fingerprint) or { assert err.msg().contains('document field'); rejected += 1 }
		assert rejected == 2, invalid
		assert os.read_file(service.root + '/etc/vinix-packages/config.json')! == configuration
		assert service.state()! == state && os.read_file(state_directory(service.root) + '/trust-history.json')! == history
	}
	// Escaped key spelling is accepted when unique, and does not change identity.
	escaped := valid.replace('"policy":', '"pol\\u0069cy":').replace('"offline":', '"off\\u006cine":')
	os.write_file(path, escaped)!
	mut same := service.review_policy(path)!
	assert same.fingerprint == reviewed.fingerprint
	same.close()
	os.write_file(path, valid)!
	mut applied := service.apply_policy(path, reviewed.fingerprint)!
	assert applied.policy.offline && applied.policy.licenses == ['Vendor-EULA'] && applied.policy.allow_firmware
	applied.close()
	assert load_config(service.root)!.repositories == config.repositories && service.state()! == state
}

fn test_policy_review_decoder_rejects_ambiguous_and_incomplete_disclosure() {
	work, service, config := policy_fixture('review-keys', true)!
	defer { os.rmdir_all(work) or {} }
	path := policy_file(work, Policy{ ...config.policy,
		pins: [Dependency{ id: 'app' }, Dependency{ id: 'runtime' }] })!
	mut review := service.review_policy(path)!
	defer { review.close() }
	valid := json2.encode(review)
	for invalid in [
		valid.replace('"format":1', '"format":1,"format":1'),
		valid.replace('"format":1', '"format":1,"future":false'),
		valid.replace('"previous":{', '"previous":{"future":false,'),
		valid.replace('"proposed":{', '"proposed":{"format":1,'),
		valid.replace('"offline":false', '"offline":true,"offline":false'),
		valid.replace('"id":"app"', '"id":"app","id":"app"'),
		valid.replace('"id":"app"', '"id":"app","i\\u0064":"app"'),
		valid.replace('"kind":"linux"', '"kind":"linux","permissions":[]'),
		valid.replace('"proprietary":true,', ''),
		valid.replace('"firmware":true,', ''),
		valid.replace('"diagnostic_before":"",', ''),
		valid.replace('"proprietary":true', '"proprietary":"true"'),
	] {
		if mut accepted := decode_policy_review(invalid) {
			accepted.close()
			assert false, invalid
		}
	}
	mut decoded := decode_policy_review(valid)!
	assert decoded.rows.len == 2 && decoded.rows[1].proprietary && decoded.rows[1].firmware
	decoded.close()
	// JSON-looking license/diagnostic values are text, not additional keys.
	text := '{"format":1,"architecture":"aarch64","policy":{"offline":false,"allowed":[],"pins":[{"id":"app","minimum":"","before":""},{"id":"runtime","minimum":"","before":""}],"permissions":[],"licenses":["{\\\"offline\\\":true}","braces [] {} and \\\"quotes\\\""],"allow_firmware":false,"reserve_bytes":0}}'
	input := json2.decode[PolicyFile](text, strict: true)!
	document_keys(text, policy_document_field)!
	assert input.policy.licenses.len == 2
}
