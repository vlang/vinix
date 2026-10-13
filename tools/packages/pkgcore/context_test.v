// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.appsdk

fn test_application_context_is_derived_from_installed_state_and_preserved_across_launch_modes() {
	key := '0123456789abcdef'.repeat(4)
	runtime := Package{ id: 'runtime', version: '2.1.0', architecture: 'aarch64', name: 'Runtime', license: 'MIT', kind: 'runtime',
		files: [Payload{ path: 'bin/runner', sha256: 'a'.repeat(64), bytes: 1, executable: true }] }
	app := Package{ id: 'app', version: '1.2.3', architecture: 'aarch64', name: 'App', license: 'MIT', kind: 'linux',
		runtime: 'runtime', entrypoint: 'bin/runner', permissions: ['files'], dependencies: [Dependency{ id: 'runtime' }],
		files: [Payload{ path: 'file', sha256: 'b'.repeat(64), bytes: 1 }] }
	state := State{ architecture: 'aarch64', generation: 42, requested: ['app'], packages: [
		Installed{ package: app, repository: 'publisher', public_key: key, sequence: 7 },
		Installed{ package: runtime, repository: 'publisher', public_key: key, sequence: 8 }] }
	config := Config{ architecture: 'aarch64', repositories: [Repository{ id: 'publisher', public_key: key }] }
	for launch in [launch_plan(config, '/var/lib/vinix-packages', state, 'app', '/home/user/data', 1000, 1000, [])!,
		command_launch_plan(config, '/var/lib/vinix-packages', state, 'app', '/home/user/data', 1000, 1000, CommandLaunch{ data_cwd: true }, false)!,
		terminal_launch_plan(config, '/var/lib/vinix-packages', state, 'app', '/home/user/data', 1000, 1000, [])!] {
		for value in ['VINIX_APP_ID=app', 'VINIX_APP_VERSION=1.2.3', 'VINIX_APP_GENERATION=42', 'VINIX_APP_SEQUENCE=7',
			'VINIX_APP_RUNTIME_ID=runtime', 'VINIX_APP_RUNTIME_VERSION=2.1.0', 'VINIX_APP_PERMISSIONS=files'] { assert value in launch.arguments }
		assert launch.arguments.filter(it.starts_with('VINIX_APP_')).len == 15
		assert launch.arguments.filter(it == '--env').len < 64
	}
	// The library validates this same generation namespace independently of the service.
	mut context := appsdk.decode(appsdk.Fields{ sdk: '1', id: app.id, version: app.version, architecture: 'aarch64', kind: app.kind,
		generation: '42', repository: 'publisher', public_key: key, sequence: '7',
		app_directory: '/var/lib/vinix-packages/generations/42/apps/app', data_directory: '/home/user/data',
		runtime_id: 'runtime', runtime_version: '2.1.0', runtime_directory: '/var/lib/vinix-packages/generations/42/apps/runtime', permissions: 'files' })!
	context.close()
}
