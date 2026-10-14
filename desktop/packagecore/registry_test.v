// SPDX-License-Identifier: GPL-2.0-or-later
module packagecore

import json2
import os

struct Manifest {
	id string
	name string
	description string
	architecture string
	kind string
	permissions []string
	associations []string
}

struct Installed {
	package Manifest
}

struct FixtureState {
	format       int
	generation   u64
	architecture string
	packages     []Installed
}

fn fixture_manifest(id string, kind string, permissions []string) Manifest {
	return Manifest{
		id:           id
		name:         id
		description:  ''
		architecture: 'aarch64'
		kind:         kind
		permissions:  permissions
		associations: ['text/plain']
	}
}

fn rejected_refresh(mut registry Registry, directory string, owner u32, architecture string) bool {
	registry.refresh(directory, owner, architecture) or { return true }
	return false
}

fn test_generation_registration_rejects_forgery_and_has_bounded_lifetimes() {
	root := os.real_path(os.temp_dir()) + '/vinix-launcher-registry-' + os.getpid().str()
	os.mkdir_all(root + '/generations/1')!
	defer { os.rmdir_all(root) or {} }
	for path in [root, root + '/generations', root + '/generations/1'] { os.chmod(path, 0o755)! }
	owner := u32(os.geteuid())
	mut registry := Registry{}
	defer { registry.close() }
	assert !registry.refresh(root, owner, 'aarch64')!
	state := FixtureState{
		format:       1
		generation:   1
		architecture: 'aarch64'
		packages:     [
			Installed{ package: fixture_manifest('z-editor', 'native', ['files']) },
			Installed{ package: fixture_manifest('a-app', 'windows', []) },
			Installed{ package: fixture_manifest('runtime', 'runtime', []) },
			Installed{ package: fixture_manifest('data', 'data', []) },
		]
	}
	path := root + '/generations/1/state.json'
	encoded := json2.encode(state)
	os.write_file(path, encoded)!
	os.chmod(path, 0o644)!
	os.symlink('generations/1', root + '/current')!
	assert registry.refresh(root, owner, 'aarch64')!
	assert registry.apps.len == 2
	assert registry.apps[0].id == 'a-app'
	assert !registry.apps[0].accepts('text/plain')
	assert registry.apps[1].open_action == 'session.open.package.z-editor'
	assert (registry.handler('package.z-editor', 'text/plain') or { panic('missing handler') }) == 'z-editor'
	assert rejected_refresh(mut registry, root, owner, 'x86_64')
	assert rejected_refresh(mut registry, root, owner + 1, 'aarch64')
	// Repeated metadata reload and retirement uses exactly the UI's explicit
	// ownership path, without a collector hiding double frees.
	for _ in 0 .. 200 {
		assert !registry.refresh(root, owner, 'aarch64')!
		registry.close()
		assert registry.refresh(root, owner, 'aarch64')!
	}
	os.chmod(path, 0o666)!
	assert rejected_refresh(mut registry, root, owner, 'aarch64')
	os.chmod(path, 0o644)!
	os.write_file(path, json2.encode(FixtureState{ ...state, generation: 2 }))!
	assert rejected_refresh(mut registry, root, owner, 'aarch64')
	os.write_file(path, json2.encode(FixtureState{ ...state, packages: [
		state.packages[0],
		state.packages[0],
	] }))!
	assert rejected_refresh(mut registry, root, owner, 'aarch64')
	os.rm(path)!
	os.write_file(root + '/outside.json', encoded)!
	os.symlink(root + '/outside.json', path)!
	assert rejected_refresh(mut registry, root, owner, 'aarch64')
	os.rm(root + '/current')!
	os.symlink('../outside', root + '/current')!
	assert rejected_refresh(mut registry, root, owner, 'aarch64')
	os.rm(root + '/current')!
	assert registry.refresh(root, owner, 'aarch64')!
	assert registry.apps.len == 0
}

fn test_request_keeps_literal_documents_and_rejects_control_characters() {
	request := Request{ id: 'editor', document: '/home/user/a space; \$literal.txt' }
	request.validate()!
	assert json2.decode[Request](json2.encode(request))! == request
	for bad in [Request{ id: 'editor;sh' }, Request{ id: 'editor', document: 'relative' },
		Request{ id: 'editor', document: '/tmp/a\nline' }] {
		mut rejected := false
		bad.validate() or { rejected = true }
		assert rejected
	}
}

fn test_registration_rejects_damaged_metadata_without_publishing_partial_menus_and_recovers() {
	root := os.real_path(os.temp_dir()) + '/vinix-registration-admission-' + os.getpid().str()
	os.mkdir_all(root + '/generations/1')!
	defer { os.rmdir_all(root) or {} }
	owner := u32(os.geteuid())
	path := root + '/generations/1/state.json'
	valid := json2.encode(FixtureState{format: 1, generation: 1, architecture: 'x86_64', packages: [
		Installed{package: Manifest{ ...fixture_manifest('editor', 'native', ['files']), architecture: 'x86_64' }},
		Installed{package: Manifest{ ...fixture_manifest('runtime', 'runtime', []), architecture: 'x86_64' }},
	]})
	os.write_file(path, valid)!
	os.mkdir_all(root + '/generations/2')!
	os.link(path, root + '/generations/2/state.json')!
	os.symlink('generations/1', root + '/current')!
	mut registry := Registry{}
	defer { registry.close() }
	assert registry.refresh(root, owner, 'x86_64')!
	assert registry.apps.len == 1 && registry.apps[0].id == 'editor' && registry.apps[0].accepts('text/plain')
	// Equal file identities do not authorize a different activation generation.
	os.rm(root + '/current')!; os.symlink('generations/2', root + '/current')!
	assert rejected_refresh(mut registry, root, owner, 'x86_64') && registry.generation == 1
	os.rm(root + '/current')!; os.symlink('generations/1', root + '/current')!
	assert !registry.refresh(root, owner, 'x86_64')!
	for invalid in [
		'{"format":1,"generation":1,"architecture":"x86_64","packages":null}',
		'{"format":1,"generation":1,"architecture":"x86_64"}',
		valid.replace('"permissions":["files"]', '"permissions":null'),
		valid.replace('"id":"runtime"', '"id":"runtime","i\\u0064":"other"'),
		valid.replace('"associations":["text/plain"]', '"associations":null'),
		valid + ' false', valid[..valid.len - 2],
	] {
		// Replace the inode so a rejected parse cannot be hidden by the identity cache.
		os.write_file(path + '.new', invalid)!; os.rename(path + '.new', path)!
		assert rejected_refresh(mut registry, root, owner, 'x86_64')
		assert registry.generation == 1 && registry.apps.len == 1 && registry.apps[0].id == 'editor'
		assert registry.apps[0].accepts('text/plain')
	}
	os.write_file(path + '.new', valid)!; os.rename(path + '.new', path)!
	assert registry.refresh(root, owner, 'x86_64')! && !registry.refresh(root, owner, 'x86_64')!
	// Service-generated canonical positive u64 identities and the maximum value
	// are admitted; aliases and overflow cannot become another menu generation.
	for number in ['0', '01', '+1', '-1', '1.0', '18446744073709551616', '18446744073709551617', '18446744073709551615'] {
		os.mkdir_all(root + '/generations/' + number)!
		os.write_file(root + '/generations/' + number + '/state.json', valid.replace('"generation":1', '"generation":' + number))!
		os.rm(root + '/current')!; os.symlink('generations/' + number, root + '/current')!
		if number == '18446744073709551615' {
			assert registry.refresh(root, owner, 'x86_64')! && registry.generation == ~u64(0)
		} else {
			assert rejected_refresh(mut registry, root, owner, 'x86_64') && registry.generation == 1
		}
	}
	os.rm(root + '/current')!; os.symlink('generations/1', root + '/current')!
	assert registry.refresh(root, owner, 'x86_64')!
	os.write_file(path + '.new', '{"format":1,"generation":1,"architecture":"x86_64","packages":[]}')!
	os.rename(path + '.new', path)!
	assert registry.refresh(root, owner, 'x86_64')! && registry.apps.len == 0 && registry.generation == 1
}
