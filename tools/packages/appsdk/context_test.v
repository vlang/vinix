// SPDX-License-Identifier: MIT
module appsdk

fn fixture_fields() Fields {
	return Fields{ sdk: '1', id: 'org.example.app', version: '1.2.3', architecture: 'aarch64', kind: 'native',
		generation: '42', repository: 'publisher', public_key: '0123456789abcdef'.repeat(4), sequence: '7',
		app_directory: '/var/lib/vinix-packages/generations/42/apps/org.example.app', data_directory: '/home/user/a space; $literal',
		runtime_id: '', runtime_version: '1.2.3', runtime_directory: '/var/lib/vinix-packages/generations/42/apps/org.example.app',
		permissions: 'files network' }
}

fn test_context_decodes_owned_values_and_canonical_environment_without_shell_expansion() {
	fields := fixture_fields()
	mut context := decode(fields)!
	assert context.id == fields.id && context.generation == 42 && context.sequence == 7
	assert context.declares('files') && !context.declares('process')
	mut environment := context.environment()!
	assert environment.len == 15 && 'VINIX_APP_PERMISSIONS=files network' in environment
	assert 'VINIX_APP_DATA=/home/user/a space; $literal' in environment
	free_values(mut environment)
	context.close(); context.close()
	assert context.id == '' && context.permissions.len == 0 && fields.id == 'org.example.app'
	unsafe { fields.public_key.free() }
}

fn test_context_supports_all_app_kinds_and_explicit_same_generation_runtimes() {
	base := fixture_fields()
	defer { unsafe { base.public_key.free() } }
	for kind in ['native', 'linux', 'windows', 'apple'] {
		mut context := decode(Fields{ ...base, kind: kind, runtime_id: 'runtime', runtime_version: '2.0.0',
			runtime_directory: '/var/lib/vinix-packages/generations/42/apps/runtime', permissions: '' })!
		assert context.kind == kind && context.runtime_version == '2.0.0' && context.permissions.len == 0
		context.close()
	}
	assert counter('18446744073709551615')! == ~u64(0)
}

fn test_context_refuses_malformed_bounds_counters_paths_permissions_and_partial_runtime_fields() {
	base := fixture_fields()
	defer { unsafe { base.public_key.free() } }
	for fields in [Fields{ ...base, sdk: '2' }, Fields{ ...base, id: '../escape' }, Fields{ ...base, version: '01.2.3' },
		Fields{ ...base, architecture: 'arm64' }, Fields{ ...base, kind: 'data' }, Fields{ ...base, generation: '0' },
		Fields{ ...base, generation: '042' }, Fields{ ...base, sequence: '18446744073709551616' }, Fields{ ...base, sequence: '-1' },
		Fields{ ...base, repository: '' }, Fields{ ...base, public_key: 'F'.repeat(64) },
		Fields{ ...base, app_directory: '/var/lib/vinix-packages/generations/41/apps/org.example.app' },
		Fields{ ...base, data_directory: '/home/user/../outside' }, Fields{ ...base, data_directory: '/home/user/nul\x00' },
		Fields{ ...base, data_directory: '/home//user/data' }, Fields{ ...base, data_directory: '/' + 'x'.repeat(4096) },
		Fields{ ...base, runtime_version: '2.0.0' }, Fields{ ...base, runtime_id: 'runtime' },
		Fields{ ...base, runtime_id: 'runtime', runtime_directory: '/var/lib/vinix-packages/generations/41/apps/runtime' },
		Fields{ ...base, permissions: 'files files' }, Fields{ ...base, permissions: 'files  network' },
		Fields{ ...base, permissions: 'files\nnetwork' }, Fields{ ...base, permissions: 'root' }, Fields{ ...base, permissions: 'x'.repeat(65) }] {
		mut refused := false
		decode(fields) or { refused = true; unsafe { err.free() } }
		assert refused
	}
}
