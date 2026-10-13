// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2

fn test_native_window_launch_keeps_only_standard_streams_and_declared_paths() {
	for architecture in ['aarch64', 'x86_64'] {
		key := 'a'.repeat(64)
		config := Config{ architecture: architecture, launch_user: 'alex', repositories: [Repository{ id: 'publisher', url: 'https://example.invalid', public_key: key }] }
		p := Package{ id: 'counter', version: '1.0.0', architecture: architecture, name: 'Counter', license: 'MIT', kind: 'native', entrypoint: 'bin/counter',
			window_protocol: 1, permissions: ['display'], files: [Payload{ path: 'bin/counter', sha256: key, bytes: 1, executable: true }] }
		state := State{ generation: 1, architecture: architecture, requested: ['counter'], packages: [Installed{ package: p, repository: 'publisher', public_key: key, sequence: 1 }] }
		launch := application_launch_plan(config, '/var/lib/vinix-packages', state, p.id, '/home/alex/data', 1000, 1000, LaunchInput{ window: true })!
		assert 'VINIX_WINDOW_PROTOCOL=1' in launch.arguments
		assert launch.arguments.all(!it.starts_with('DISPLAY='))
		assert '/tmp/.X11-unix' !in launch.arguments && '/dev' !in launch.arguments && '/dev/dri' !in launch.arguments
		assert 'unix' !in launch.arguments[launch.arguments.index('--promises') + 1].split(' ')
		assert 'tty' !in launch.arguments[launch.arguments.index('--promises') + 1].split(' ')
		assert launch_session_request(config, '/usr/bin/vinix-package', p.id, LaunchInput{ window: true })!.arguments
			== ['run', '--isolated', 'alex', '/usr/bin/vinix-package', 'run-window', 'counter']
		for invalid in [Package{ ...p, window_protocol: 2 }, Package{ ...p, permissions: [] }, Package{ ...p, kind: 'data', architecture: 'all' }] {
			mut refused := false
			invalid.validate() or { refused = true }
			assert refused
		}
		for denied in [Config{ ...config, repositories: [] }, Config{ ...config, policy: Policy{ permissions: [] } }] {
			mut refused := false
			application_launch_plan(denied, '/var/lib/vinix-packages', state, p.id, '/home/alex/data', 1000, 1000, LaunchInput{ window: true }) or { refused = true }
			assert refused
		}
		legacy := Package{ ...p, window_protocol: 0 }
		assert !json2.encode(legacy).contains('window_protocol')
		assert json2.encode(p).contains('"window_protocol":1')
		legacy_state := State{ ...state, packages: [Installed{ ...state.packages[0], package: legacy }] }
		pending := catalog_view(config, Catalog{ packages: state.packages }, legacy_state, '')!
		assert pending.rows[0].installed_window_protocol == 0 && pending.rows[0].updatable
		mut refused := false
		application_launch_plan(config, '/var/lib/vinix-packages', legacy_state, p.id, '/home/alex/data', 1000, 1000, LaunchInput{ window: true }) or { refused = true }
		assert refused
		view := catalog_view(config, Catalog{}, state, 'offline')!
		assert view.rows[0].installed_window_protocol == 1
	}
}
