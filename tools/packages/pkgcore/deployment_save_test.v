// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os
import time

fn saved_deployment_fixture(architecture string) !string {
	work := os.real_path(os.temp_dir()) + '/vinix-deployment-save-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/etc/vinix-packages')!
	os.write_file(work + '/etc/vinix-packages/config.json', json2.encode(Config{ architecture: architecture,
		policy: Policy{ offline: true, allowed: ['unrelated'], permissions: [], reserve_bytes: 0 } }))!
	mut packages := []Installed{}
	for id in ['app', 'runtime', 'assets', 'extra'] {
		p := Package{ id: id, name: id, version: '1.0.0', architecture: if id in ['assets', 'extra'] { 'all' } else { architecture },
			kind: if id in ['assets', 'extra'] { 'data' } else if id == 'runtime' { 'runtime' } else { 'linux' }, license: 'MIT',
			runtime: if id == 'app' { 'runtime' } else { '' }, entrypoint: if id == 'app' { 'bin/runner' } else { '' },
			dependencies: if id == 'app' { [Dependency{ id: 'runtime' }] } else if id == 'runtime' { [Dependency{ id: 'assets' }] } else { []Dependency{} },
			files: [Payload{ path: 'bin/runner', bytes: 7, sha256: sha256.sum('payload'.bytes()).hex(), executable: true }] }
		packages << Installed{ package: p, repository: 'historical', sequence: 17,
			public_key: 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a' }
	}
	state := State{ architecture: architecture, generation: 7, requested: ['extra', 'app'], packages: packages }
	validate_state(state, architecture)!
	directory := state_directory(work)
	guard := acquire(directory)!; defer { guard.release() }
	os.mkdir(directory + '/generations/7')!
	os.write_file(directory + '/generations/7/state.json', encode_generation_state(state)!)!
	os.symlink('generations/7', directory + '/current')!
	os.write_file(directory + '/catalog.json', 'unavailable catalog')!; os.write_file(directory + '/trust-history.json', 'unavailable history')!
	return work
}

fn test_saved_deployment_is_exact_sorted_offline_and_reports_the_captured_generation_and_bytes() {
	for architecture in ['aarch64', 'x86_64'] {
		work := saved_deployment_fixture(architecture)!; defer { os.rmdir_all(work) or {} }
		service := Service{ root: work }; directory := state_directory(work)
		before := read_metadata(directory + '/current/state.json')!
		mut snapshot := service.snapshot_deployment([])!; defer { snapshot.close() }
		for roots in [[]string{}, ['runtime']] {
			path := work + if roots.len == 0 { '/saved é; $literal.json' } else { '/subset.json' }
			mut saved := service.save_deployment_snapshot(path, roots)!; defer { saved.close() }
			text := read_metadata(path)!
			assert saved.generation == 7 && saved.architecture == architecture && saved.destination == path
			assert saved.sha256 == sha256.sum(text.bytes()).hex() && text.ends_with('\n') && os.lstat(path)!.mode & 0o777 == 0o644
			mut decoded := decode_deployment(text, architecture)!; defer { decoded.close() }
			if roots.len == 0 {
				assert text == json2.encode(snapshot) + '\n' && saved.roots == 2 && saved.packages == 4
				mut audit := service.audit_deployment(path)!; assert audit.matches; audit.close()
			} else { assert decoded.packages == ['runtime'] && decoded.locked.map(it.id) == ['assets', 'runtime'] && saved.roots == 1 && saved.packages == 2 }
			assert decoded.locked.all(it.minimum_sequence == 17 && it.version == '1.0.0')
			saved.close(); saved.close()
			assert read_metadata(path)! == text
		}
		assert read_metadata(directory + '/current/state.json')! == before && os.ls(directory + '/generations')! == ['7']
		assert read_metadata(directory + '/catalog.json')! == 'unavailable catalog' && read_metadata(directory + '/trust-history.json')! == 'unavailable history'
		assert os.ls(directory + '/objects')!.len == 0 && os.ls(work)!.all(!it.starts_with('.package-'))
	}
	println('DEPLOYMENT SAVE exact sorted installed app/runtime/all-data metadata, subset closure, generation/digest receipt, offline revoked policy and no source mutation on both architectures PASS')
}

fn test_saved_deployment_refuses_bad_roots_corrupt_state_writer_and_existing_output_without_creating_partial_files() {
	work := saved_deployment_fixture('aarch64')!; defer { os.rmdir_all(work) or {} }
	service := Service{ root: work }; directory := state_directory(work); path := work + '/saved'
	for roots in [['missing'], ['app', 'app'], ['../app'], ['app'].repeat(4097)] {
		mut refused := false; service.save_deployment_snapshot(path, roots) or { refused = true }; assert refused && !os.exists(path)
	}
	for invalid in ['', path + '\x00ignored', work + '/bad\nname', work + '/bad\xff', 'x'.repeat(4097), work + '/missing/child'] {
		mut refused := false; service.save_deployment_snapshot(invalid, []) or { refused = true }; assert refused
	}
	mut saved := service.save_deployment_snapshot(path, [])!; saved.close()
	before := read_metadata(path)!
	mut refused := false; service.save_deployment_snapshot(path, ['runtime']) or { refused = err.msg().contains('already exists') }; assert refused && read_metadata(path)! == before
	configuration := read_metadata(work + '/etc/vinix-packages/config.json')!
	guard := acquire(directory)!; os.write_file(work + '/etc/vinix-packages/config.json', '{bad')!
	mut message := ''; service.save_deployment_snapshot(work + '/busy', []) or { message = err.msg() }
	assert message.contains('another package transaction') && !os.exists(work + '/busy'); guard.release()
	os.write_file(work + '/etc/vinix-packages/config.json', configuration)!
	os.write_file(directory + '/current/state.json', '{}')!
	refused = false; service.save_deployment_snapshot(work + '/corrupt', []) or { refused = true }; assert refused && !os.exists(work + '/corrupt')
	assert os.ls(work)!.all(!it.starts_with('.package-'))
	os.rmdir_all(work + '/var')!
	mut empty := service.save_deployment_snapshot(work + '/empty.json', [])!; defer { empty.close() }
	assert empty.generation == 0 && empty.roots == 0 && empty.packages == 0 && !os.exists(work + '/var')
	mut document := decode_deployment(read_metadata(work + '/empty.json')!, 'aarch64')!; defer { document.close() }
	assert document.packages.len == 0 && document.locked.len == 0
	println('DEPLOYMENT SAVE malformed roots/paths/state and busy writers refuse before output; existing files preserved, temporary cleanup and fresh empty observation PASS')
}
