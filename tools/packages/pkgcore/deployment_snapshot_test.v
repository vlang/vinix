// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os
import time

fn snapshot_fixture(architecture string) !(string, State) {
	work := os.temp_dir() + '/vinix-deployment-snapshot-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/etc/vinix-packages')!
	os.write_file(work + '/etc/vinix-packages/config.json', json2.encode(Config{ architecture: architecture,
		policy: Policy{ offline: true, allowed: ['unrelated'], permissions: [], reserve_bytes: 0 } }))!
	mut packages := []Installed{}
	for id in ['editor', 'viewer', 'runtime', 'assets', 'extra'] {
		p := Package{ id: id, name: id, description: 'Installed snapshot fixture', version: '1.0.0',
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

fn test_installed_snapshot_is_exact_sorted_offline_and_independent_of_current_policy_or_trust() {
	for architecture in ['aarch64', 'x86_64'] {
		work, state := snapshot_fixture(architecture)!; defer { os.rmdir_all(work) or {} }
		service := Service{ root: work }
		directory := state_directory(work)
		before := os.read_file(directory + '/current/state.json')!
		mut full := service.snapshot_deployment([])!; defer { full.close() }
		assert full.format == 2 && full.architecture == architecture
		assert full.packages == ['editor', 'extra', 'viewer']
		assert full.locked.map(it.id) == ['assets', 'editor', 'extra', 'runtime', 'viewer']
		for pin in full.locked {
			p := state.packages.filter(it.package.id == pin.id)[0]
			assert pin.version == p.package.version && pin.architecture == p.package.architecture
			assert pin.repository == p.repository && pin.public_key == p.public_key && pin.minimum_sequence == p.sequence
			assert pin.metadata_sha256 == package_metadata_digest(p.package)!
		}
		mut selected := service.snapshot_deployment(['viewer'])!; defer { selected.close() }
		assert selected.packages == ['viewer'] && selected.locked.map(it.id) == ['assets', 'runtime', 'viewer']
		mut dependency := service.snapshot_deployment(['runtime'])!; defer { dependency.close() }
		assert dependency.packages == ['runtime'] && dependency.locked.map(it.id) == ['assets', 'runtime']
		assert os.read_file(directory + '/current/state.json')! == before
		assert os.read_file(directory + '/catalog.json')! == 'unavailable catalog'
		assert os.read_file(directory + '/trust-history.json')! == 'unavailable history'
		assert os.ls(directory + '/objects')!.len == 0 && os.ls(directory + '/generations')! == ['7']
	}
	println('DEPLOYMENT SNAPSHOT exact sorted roots, shared runtime/all-data closure, metadata/provenance/sequence pins, offline revoked policy independence and no mutation on both architectures PASS')
}

fn test_snapshot_owns_returned_documents_and_refuses_invalid_or_uninstalled_roots() {
	work, state := snapshot_fixture('aarch64')!; defer { os.rmdir_all(work) or {} }
	service := Service{ root: work }
	for names in [['viewer', 'viewer'], ['missing'], ['../editor'], [''], ['viewer'].repeat(4097)] {
		mut refused := false
		service.snapshot_deployment(names) or { refused = true; unsafe { err.free() } }
		assert refused
	}
	for _ in 0 .. 32 {
		mut document := service.snapshot_deployment(['viewer', 'editor'])!
		text := json2.encode(document)
		document.close(); document.close()
		assert document.locked.len == 0 && document.packages.len == 0 && document.architecture == ''
		decoded := decode_deployment(text, 'aarch64')!
		assert decoded.packages == ['editor', 'viewer'] && decoded.locked.len == 4
		assert state.packages[0].package.id == 'editor'
	}
	println('DEPLOYMENT SNAPSHOT independently owned closeable documents and invalid/duplicate/missing/excess roots refusal PASS')
}

fn test_snapshot_is_read_only_on_fresh_state_and_excludes_writers_before_configuration_reads() {
	work, _ := snapshot_fixture('aarch64')!; defer { os.rmdir_all(work) or {} }
	service := Service{ root: work }; directory := state_directory(work)
	configuration := os.read_file(work + '/etc/vinix-packages/config.json')!
	guard := acquire(directory)!
	os.write_file(work + '/etc/vinix-packages/config.json', '{bad')!
	mut message := ''
	service.snapshot_deployment([]) or { message = err.msg() }
	assert message.contains('another package transaction')
	guard.release()
	os.write_file(work + '/etc/vinix-packages/config.json', configuration)!
	os.write_file(directory + '/current/state.json', '{}')!
	mut refused := false; service.snapshot_deployment([]) or { refused = true }; assert refused
	os.rmdir_all(work + '/var')!
	mut empty := service.snapshot_deployment([])!; defer { empty.close() }
	assert empty.locked.len == 0 && empty.packages.len == 0 && !os.exists(work + '/var')
	refused = false; service.snapshot_deployment(['viewer']) or { refused = true }; assert refused && !os.exists(work + '/var')
	println('DEPLOYMENT SNAPSHOT fresh empty read without initialization, writer exclusion and malformed state refusal PASS')
}
