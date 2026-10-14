// SPDX-License-Identifier: MIT
module appsdk

fn test_permission_sets_support_every_subset_and_keep_context_environment_canonical() {
	key := 'a'.repeat(64)
	defer { unsafe { key.free() } }
	for architecture in ['aarch64', 'x86_64'] {
		for mask in 0 .. 32 {
			mut values := []string{cap: 5}
			for index, value in ['process', 'network', 'files', 'display', 'audio']! {
				if mask & (1 << index) != 0 { values << value }
			}
			assert valid_permissions(values)
			context := Context{id: 'app', version: '1.0.0', architecture: architecture, kind: 'native', generation: 1,
				repository: 'publisher', public_key: key, sequence: 1,
				app_directory: '/var/lib/vinix-packages/generations/1/apps/app', data_directory: '/home/user/data',
				runtime_version: '1.0.0', runtime_directory: '/var/lib/vinix-packages/generations/1/apps/app', permissions: values}
			mut environment := context.environment()!
			mut sorted := values.clone(); sorted.sort()
			text := sorted.join(' ')
			expected := 'VINIX_APP_PERMISSIONS=' + text
			assert expected in environment
			free_values(mut environment)
			free_values(mut values)
			unsafe { (&array(&sorted)).free(); text.free(); expected.free() }
		}
	}
}

fn test_permission_sets_refuse_repetition_unknown_names_and_excess_entries() {
	for invalid in [['files', 'files'], ['audio', 'display', 'files', 'network', 'process', 'files'],
		['root'], ['Files'], [''], ['files network'], ['files\x00'], ['files', 'network', 'files']] {
		assert !valid_permissions(invalid)
	}
}
