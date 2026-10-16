// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

fn test_apple_containers_follow_admitted_private_data_in_every_launch_mode_without_extra_grants() {
	key := 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
	os.setenv('VINIX_IOS_DOCUMENTS', '/ambient/Documents', true)
	os.setenv('VINIX_IOS_KEYCHAIN', '/ambient/Keychains', true)
	for architecture in ['aarch64', 'x86_64'] {
		runtime := Package{ id: 'runtime', version: '1.0.0', architecture: architecture, name: 'Runtime', license: 'MIT', kind: 'runtime',
			files: [Payload{ path: 'bin/runner', sha256: key, bytes: 1, executable: true }] }
		for kind in ['native', 'linux', 'windows', 'apple'] {
			app := Package{ id: 'app', version: '1.0.0', architecture: architecture, name: 'App', license: 'MIT', kind: kind,
				runtime: 'runtime', entrypoint: 'bin/runner', dependencies: [Dependency{ id: 'runtime' }],
				files: [Payload{ path: 'payload', sha256: key, bytes: 1 }] }
			state := State{ architecture: architecture, generation: 7, requested: ['app'], packages: [
				Installed{ package: app, repository: 'fixture', public_key: key, sequence: 1 },
				Installed{ package: runtime, repository: 'fixture', public_key: key, sequence: 1 }] }
			config := Config{ architecture: architecture, repositories: [Repository{ id: 'fixture', public_key: key }] }
			data := '/home/user/private é ; $data'
			for mode in 0 .. 4 {
				mut plan := application_launch_plan(config, '/var/lib/vinix-packages', state, 'app', data, 1000, 1000,
					LaunchInput{ terminal: mode in [1, 3], command: mode in [2, 3], data_cwd: mode == 3 })!
				defer { plan.close() }
				extras := plan.arguments.filter(it.starts_with('VINIX_IOS_'))
				assert extras == if kind == 'apple' { ['VINIX_IOS_DOCUMENTS=' + data + '/Documents', 'VINIX_IOS_KEYCHAIN=' + data + '/Keychains'] } else { []string{} }
				assert !plan.arguments.any(it.contains('/ambient/'))
				assert plan.arguments.count(it == '--unveil') == 3 // app, private data, runtime
				promises := 'stdio rpath wpath cpath flock exec prot_exec' + if mode in [1, 3] { ' tty' } else { '' }
				assert promises in plan.arguments
			}
		}
	}
}
