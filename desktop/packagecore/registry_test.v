// SPDX-License-Identifier: GPL-2.0-or-later
module packagecore

import json2
import os

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
