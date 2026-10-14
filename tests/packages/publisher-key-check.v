// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import tools.packages.pkgcore
import tools.packages.pkgprotocol

fn forged(sequence u64) string {
	return '{"format":1,"repository":"fixture","sequence":${sequence},"expires":2000000000,"packages":[]}'
}

fn refused(message string) {
	assert message.contains('publisher key'), message
}

fn check() ! {
	assert os.args.len == 2
	before := os.args[1] == '--before'
	weak := '01' + '00'.repeat(31)
	sig := '01' + '00'.repeat(63)
	for sequence in [u64(1), 1000000] {
		if index := pkgcore.verify_index(pkgcore.Repository{ id: 'fixture', public_key: weak }, forged(sequence), sig, 1900000000) {
			assert before && index.sequence == sequence
		} else {
			assert !before
			refused(err.msg())
		}
	}
	if before { println('Publisher key baseline: same fabricated signature authenticated two identity-key indexes'); return }
	work := os.abs_path(os.args[1])
	assert !os.exists(work) && !os.is_link(work)
	os.mkdir_all(work + '/etc/vinix-packages')!
	defer { os.rmdir_all(work) or {} }
	config_path := work + '/etc/vinix-packages/config.json'
	initial := pkgcore.Config{ architecture: 'aarch64', policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }
	os.write_file(config_path, json2.encode(initial))!
	os.chmod(config_path, 0o644)!
	os.mkdir(work + '/repository')!
	os.write_file(work + '/repository/index.json', forged(1000000))!
	os.write_file(work + '/repository/index.sig', sig)!
	bad := pkgcore.Repository{ id: 'fixture', url: 'file://' + work + '/repository', public_key: weak }
	configuration := os.read_file(config_path)!
	if _ := pkgcore.review_repository(work, 'enroll', bad, true) { assert false } else { refused(err.msg()) }
	assert os.read_file(config_path)! == configuration
	assert !os.exists(pkgcore.state_directory(work))
	if _ := pkgcore.enroll_repository(work, bad, true) { assert false } else { refused(err.msg()) }
	assert os.read_file(config_path)! == configuration
	assert !os.exists(pkgcore.state_directory(work) + '/enrollment')
	assert !os.exists(pkgcore.state_directory(work) + '/trust-history.json')
	println('PUBLISHER KEY forged indexes and first enrollment refused PASS')
	// Build a legitimate package with public reference credentials, not release credentials.
	os.mkdir(work + '/source')!
	os.write_file(work + '/source/payload', 'payload')!
	os.write_file(work + '/manifest.json', json2.encode(pkgcore.Package{ id: 'data', name: 'Data',
		version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT' }))!
	pkgcore.pack(work + '/manifest.json', work + '/source', work + '/repository')!
	os.write_file(work + '/seed', '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60\n')!
	os.chmod(work + '/seed', 0o600)!
	pkgcore.publish(work + '/repository', 'fixture', work + '/seed', 1, 2000000000)!
	key := 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
	good := pkgcore.Repository{ ...bad, public_key: key }
	review := pkgcore.review_repository(work, 'enroll', good, true)!
	pkgcore.enroll_repository_reviewed(work, good, true, review.fingerprint)!
	service := pkgcore.Service{ root: work, offline: true }
	service.refresh()!
	service.transact('install', ['data'], pkgcore.TransactionOptions{})!
	os.write_file(work + '/manifest.json', json2.encode(pkgcore.Package{ id: 'data', name: 'Data',
		version: '1.0.1', architecture: 'all', kind: 'data', license: 'MIT' }))!
	pkgcore.pack(work + '/manifest.json', work + '/source', work + '/repository')!
	pkgcore.publish(work + '/repository', 'fixture', work + '/seed', 2, 2000000000)!
	service.refresh()!
	state := service.transact('upgrade', [], pkgcore.TransactionOptions{})!
	assert state.previous > 0
	assert state.packages.len == 1
	trusted := os.read_file(config_path)!
	history_path := pkgcore.state_directory(work) + '/trust-history.json'
	history := os.read_file(history_path)!
	os.write_file(work + '/repository/index.json', forged(1000000))!
	os.write_file(work + '/repository/index.sig', sig)!
	if _ := pkgcore.review_repository(work, 'enroll', bad, true) { assert false } else { refused(err.msg()) }
	if _ := pkgcore.enroll_repository(work, bad, true) { assert false } else { refused(err.msg()) }
	assert os.read_file(config_path)! == trusted && os.read_file(history_path)! == history
	assert service.state()!.generation == state.generation
	println('PUBLISHER KEY valid enrollment/install and rejected replacement preserve trust/history/state PASS')
	// Model an already installed legacy weak-key repository. Its syntax must stay
	// readable so the administrator can revoke it and remove its installed files.
	os.write_file(config_path, json2.encode(pkgcore.Config{ ...initial, repositories: [bad] }))!
	old_state := pkgcore.State{ ...state, packages: [pkgcore.Installed{ ...state.packages[0], public_key: weak }] }
	os.write_file(pkgcore.state_directory(work) + '/generations/' + state.generation.str() + '/state.json', json2.encode(old_state))!
	os.write_file(pkgcore.state_directory(work) + '/generations/' + state.previous.str() + '/state.json', json2.encode(
		pkgcore.State{ ...old_state, generation: state.previous, previous: 0 }))!
	os.write_file(pkgcore.state_directory(work) + '/catalog.json', json2.encode([
		pkgcore.Snapshot{ repository: bad, text: forged(1000000), signature: sig },
	]))!
	personal := work + '/home/user/.local/share/vinix-apps/data'
	os.mkdir_all(personal)!
	os.write_file(personal + '/note', 'retained')!
	legacy_config := os.read_file(config_path)!
	legacy_catalog := os.read_file(pkgcore.state_directory(work) + '/catalog.json')!
	view := pkgcore.software_view(work, true)!
	assert view.catalog_error.contains('publisher key') && view.rows.len == 1
	assert view.rows[0].diagnostic.contains('data: repository fixture has an invalid publisher key')
	assert view.rows[0].diagnostic.contains('uninstall remains available')
	mut decoded := pkgprotocol.decode_software_view(json2.encode(view))!
	assert decoded.rows[0].diagnostic == view.rows[0].diagnostic
	decoded.close()
	os.write_file(work + '/policy.json', json2.encode(pkgcore.PolicyDocument{ architecture: 'aarch64', policy: initial.policy }))!
	mut impact := service.review_policy(work + '/policy.json')!
	assert impact.rows.len == 1 && impact.rows[0].diagnostic_before == impact.rows[0].diagnostic_after
	assert impact.rows[0].diagnostic_before == view.rows[0].diagnostic
	impact.close()
	assert service.state()! == old_state && os.read_file(history_path)! == history
	assert os.read_file(config_path)! == legacy_config
	assert os.read_file(pkgcore.state_directory(work) + '/catalog.json')! == legacy_catalog
	assert os.read_file(personal + '/note')! == 'retained'
	println('PUBLISHER KEY Software and policy review disclose invalid installed trust without changing state/history/data PASS')
	if _ := service.refresh() { assert false } else { refused(err.msg()) }
	if _ := service.plan('upgrade', []) { assert false } else { refused(err.msg()) }
	if _ := service.rollback('') { assert false } else { refused(err.msg()) }
	native := pkgcore.Package{ ...old_state.packages[0].package, architecture: 'aarch64', kind: 'native', entrypoint: 'payload',
		files: [pkgcore.Payload{ ...old_state.packages[0].package.files[0], executable: true }] }
	weak_config := pkgcore.load_config(work)!
	weak_app := pkgcore.Installed{ ...old_state.packages[0], package: native }
	if _ := pkgcore.launch_plan(weak_config, pkgcore.state_directory(work),
		pkgcore.State{ ...old_state, packages: [weak_app] }, 'data', personal, 1000, 1000, []) { assert false } else { refused(err.msg()) }
	// A valid root publisher must not hide an invalid publisher in its runtime closure.
	runtime := pkgcore.Installed{ ...weak_app, package: pkgcore.Package{ ...native, id: 'runtime', kind: 'runtime' }, repository: 'legacy' }
	good_app := pkgcore.Installed{ ...weak_app, public_key: key,
		package: pkgcore.Package{ ...native, dependencies: [pkgcore.Dependency{ id: 'runtime' }] } }
	if _ := pkgcore.launch_plan(pkgcore.Config{ ...initial, repositories: [good, pkgcore.Repository{ ...bad, id: 'legacy' }] },
		pkgcore.state_directory(work), pkgcore.State{ ...old_state, packages: [good_app, runtime] },
		'data', personal, 1000, 1000, []) { assert false } else { refused(err.msg()) }
	assert os.read_file(history_path)! == history
	// Software diagnoses an implicit runtime, even when the app's own publisher
	// is admitted. This works with an unusable cache and follows the launch check.
	closure_state := pkgcore.State{ ...old_state, packages: [good_app, runtime] }
	os.write_file(config_path, json2.encode(pkgcore.Config{ ...initial, repositories: [good, pkgcore.Repository{ ...bad, id: 'legacy' }] }))!
	os.write_file(pkgcore.state_directory(work) + '/generations/' + state.generation.str() + '/state.json', json2.encode(closure_state))!
	closure_view := pkgcore.software_view(work, true)!
	assert closure_view.rows.len == 2 && closure_view.rows.all(it.diagnostic.contains('runtime: repository legacy has an invalid publisher key'))
	mut closure_impact := service.review_policy(work + '/policy.json')!
	assert closure_impact.rows.all(it.diagnostic_before.contains('runtime: repository legacy has an invalid publisher key')
		&& it.diagnostic_after == it.diagnostic_before)
	closure_impact.close()
	assert service.state()! == closure_state && os.read_file(history_path)! == history
	os.write_file(config_path, json2.encode(pkgcore.Config{ ...initial, repositories: [bad] }))!
	os.write_file(pkgcore.state_directory(work) + '/generations/' + state.generation.str() + '/state.json', json2.encode(old_state))!
	println('PUBLISHER KEY Software and policy review propagate implicit runtime trust denial PASS')
	revocation := pkgcore.review_repository(work, 'revoke', bad, true)!
	pkgcore.revoke_repository_reviewed(work, 'fixture', revocation.fingerprint)!
	assert pkgcore.load_config(work)!.repositories.len == 0
	remove := service.review('remove', ['data'])!
	assert service.transact('remove', ['data'], pkgcore.TransactionOptions{ expected_review: remove.fingerprint })!.packages.len == 0
	assert os.read_file(personal + '/note')! == 'retained'
	assert os.read_file(history_path)! == history
	println('PUBLISHER KEY legacy refresh/upgrade/rollback/app/dependency launch refused; reviewed revoke/uninstall preserve history/data PASS')
	println('Publisher key admission qualification passed')
}

fn main() { check() or { eprintln(err); exit(1) } }
