// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os
import time

fn audit_fixture(architecture string) !(string, State) {
	work := os.temp_dir() + '/vinix-deployment-audit-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/etc/vinix-packages')!
	os.write_file(work + '/etc/vinix-packages/config.json', json2.encode(Config{ architecture: architecture,
		policy: Policy{ offline: true, allowed: ['unrelated'], permissions: [], reserve_bytes: 0 } }))!
	mut packages := []Installed{}
	for id in ['editor', 'viewer', 'runtime', 'assets', 'extra'] {
		p := Package{ id: id, name: id, description: 'Installed audit fixture', version: '1.0.0',
			architecture: if id in ['assets', 'extra'] { 'all' } else { architecture },
			kind: if id in ['assets', 'extra'] { 'data' } else if id == 'runtime' { 'runtime' } else { 'linux' },
			license: 'MIT', runtime: if id in ['editor', 'viewer'] { 'runtime' } else { '' },
			entrypoint: if id in ['editor', 'viewer'] { 'bin/runner' } else { '' },
			dependencies: if id in ['editor', 'viewer'] { [Dependency{ id: 'runtime' }] }
				else if id == 'runtime' { [Dependency{ id: 'assets' }] } else { []Dependency{} },
			files: [Payload{ path: 'bin/runner', bytes: 7, sha256: sha256.sum('payload'.bytes()).hex(), executable: true }] }
		packages << Installed{ package: p, repository: 'historical',
			public_key: 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a', sequence: 17 }
	}
	state := State{ architecture: architecture, generation: 7, requested: ['viewer', 'editor', 'extra'], packages: packages }
	validate_state(state, architecture)!
	directory := state_directory(work)
	guard := acquire(directory)!; defer { guard.release() }
	os.mkdir(directory + '/generations/7')!
	os.write_file(directory + '/generations/7/state.json', encode_generation_state(state)!)!
	os.symlink('generations/7', directory + '/current')!
	os.write_file(directory + '/catalog.json', 'unavailable catalog')!
	os.write_file(directory + '/trust-history.json', 'unavailable history')!
	return work, state
}

fn test_audit_exact_metadata_offline_and_sequence_floor_on_both_architectures() {
	for architecture in ['aarch64', 'x86_64'] {
		work, _ := audit_fixture(architecture)!; defer { os.rmdir_all(work) or {} }
		service := Service{ root: work }; directory := state_directory(work)
		mut snapshot := service.snapshot_deployment([])!; defer { snapshot.close() }
		path := work + '/deployment é; $literal.json'; text := json2.encode(snapshot) + '\n'
		os.write_file(path, text)!
		before := os.read_file(directory + '/current/state.json')!
		mut audit := service.audit_deployment(path)!; defer { audit.close() }
		assert audit.matches && audit.generation == 7 && audit.architecture == architecture
		assert audit.deployment_sha256 == sha256.sum(text.bytes()).hex()
		assert audit.rows.map(it.id) == ['assets', 'editor', 'extra', 'runtime', 'viewer'] && audit.rows.all(it.status == 'match')
		// A newer authenticated sequence still satisfies the original floor.
		lower := DeploymentLock{ ...snapshot, locked: snapshot.locked.map(DeploymentPackage{ ...it, minimum_sequence: 1 }) }
		os.write_file(path, json2.encode(lower))!
		mut renewed := service.audit_deployment(path)!; assert renewed.matches; renewed.close()
		assert os.read_file(directory + '/current/state.json')! == before
		assert os.read_file(directory + '/catalog.json')! == 'unavailable catalog'
		assert os.read_file(directory + '/trust-history.json')! == 'unavailable history'
	}
	println('DEPLOYMENT AUDIT exact installed metadata, sorted runtime/all-data closure, captured digest, minimum sequence floors and offline revoked policy on both architectures PASS')
}

fn test_audit_reports_every_changed_field_missing_extra_and_root_drift() {
	work, _ := audit_fixture('aarch64')!; defer { os.rmdir_all(work) or {} }
	service := Service{ root: work }
	mut snapshot := service.snapshot_deployment([])!; defer { snapshot.close() }
	mut locked := snapshot.locked.clone()
	// Change only the target document. Installed state remains a valid closure.
	locked[1] = DeploymentPackage{ ...locked[1], architecture: 'all', version: '9.0.0', repository: 'different',
		public_key: 'b'.repeat(64), minimum_sequence: 18, metadata_sha256: 'c'.repeat(64) }
	locked << DeploymentPackage{ ...snapshot.locked[0], id: 'missing' }
	locked = locked.filter(it.id != 'extra')
	target := DeploymentLock{ ...snapshot, packages: ['viewer', 'runtime'], locked: locked }
	path := work + '/lock'; os.write_file(path, json2.encode(target))!
	mut report := service.audit_deployment(path)!; defer { report.close() }
	assert !report.matches && report.rows.map(it.id) == ['assets', 'editor', 'extra', 'missing', 'runtime', 'viewer']
	assert report.rows[1].status == 'changed' && report.rows[1].differences == ['architecture', 'metadata_sha256', 'public_key', 'repository', 'requested', 'sequence', 'version']
	assert report.rows[1].expected_version == '9.0.0' && report.rows[1].installed_version == '1.0.0'
	assert report.rows[2].status == 'unexpected' && report.rows[2].expected_version == ''
	assert report.rows[3].status == 'missing' && report.rows[3].installed_version == ''
	assert report.rows[4].differences == ['requested']
	mut subset := service.snapshot_deployment(['viewer'])!; defer { subset.close() }
	os.write_file(path, json2.encode(subset))!
	mut subset_audit := service.audit_deployment(path)!; defer { subset_audit.close() }
	assert !subset_audit.matches && subset_audit.rows.filter(it.status == 'unexpected').map(it.id) == ['editor', 'extra']
	println('DEPLOYMENT AUDIT missing/unexpected packages, versions, architecture, digests, publisher/repository, floor and requested-root differences PASS')
}

fn test_audit_refuses_bad_inputs_excludes_writers_and_observes_empty_state_without_initialization() {
	work, _ := audit_fixture('aarch64')!; defer { os.rmdir_all(work) or {} }
	service := Service{ root: work }; directory := state_directory(work)
	mut snapshot := service.snapshot_deployment([])!; defer { snapshot.close() }
	path := work + '/lock'; text := json2.encode(snapshot); os.write_file(path, text)!
	configuration := os.read_file(work + '/etc/vinix-packages/config.json')!
	guard := acquire(directory)!
	os.write_file(work + '/etc/vinix-packages/config.json', '{bad')!
	mut message := ''; service.audit_deployment(path) or { message = err.msg() }
	assert message.contains('another package transaction'); guard.release()
	os.write_file(work + '/etc/vinix-packages/config.json', configuration)!
	for bad in ['{}', text + '{}', text.replace('"format":2', '"format":2,"format":2'),
		json2.encode(DeploymentLock{ ...snapshot, architecture: 'x86_64' }),
		json2.encode(DeploymentLock{ ...snapshot, packages: ['absent'] }),
		'{"format":1,"architecture":"aarch64","packages":["editor"]}'] {
		os.write_file(path, bad)!
		mut refused := false; service.audit_deployment(path) or { refused = true }; assert refused
	}
	os.rm(path)!; os.symlink(directory + '/current/state.json', path)!
	mut refused := false; service.audit_deployment(path) or { refused = true }; assert refused
	os.rm(path)!; os.write_file(path, text)!
	os.write_file(directory + '/current/state.json', '{}')!
	refused = false; service.audit_deployment(path) or { refused = true }; assert refused
	os.rmdir_all(work + '/var')!
	mut missing := service.audit_deployment(path)!; defer { missing.close() }
	assert !missing.matches && missing.generation == 0 && missing.rows.all(it.status == 'missing') && !os.exists(work + '/var')
	os.write_file(path, '{"format":2,"architecture":"aarch64","packages":[],"locked":[]}')!
	mut empty := service.audit_deployment(path)!; empty.close(); empty.close()
	assert !os.exists(work + '/var')
	println('DEPLOYMENT AUDIT writer exclusion, malformed/roots-only/mismatched/aliased inputs and corrupt state refusal; empty read without initialization PASS')
}
