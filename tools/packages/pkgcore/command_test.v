// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

fn test_command_parser_requires_separator_and_preserves_literal_values() {
	input := command_launch(['--file', '/home/user/a space; $literal', '--', '', '-i', '@APP@/unchanged', '--file', '--', 'a\nb'])!
	assert input.documents == ['/home/user/a space; $literal']
	assert input.arguments == ['', '-i', '@APP@/unchanged', '--file', '--', 'a\nb']
	assert command_launch(['--'])!.arguments.len == 0
	assert command_launch(['--data-cwd', '--file', '/home/user/a', '--', '--data-cwd'])!
		== CommandLaunch{ data_cwd: true, documents: ['/home/user/a'], arguments: ['--data-cwd'] }
	for arguments in [ []string{}, ['-version'], ['--file'], ['--data-cwd', '--data-cwd', '--'], ['--file', 'relative', '--'], ['--file', '/tmp/new\nline', '--'], ['--', 'nul\x00'], ['--', 'x'.repeat(4097)]] {
		mut refused := false
		command_launch(arguments) or { refused = true }
		assert refused, arguments.str()
	}
	for input_limit in [CommandLaunch{ arguments: []string{len: 257, init: ''} },
		CommandLaunch{ documents: []string{len: 257, init: '/tmp/file'} },
		CommandLaunch{ arguments: []string{len: 16, init: 'x'.repeat(4096)} }] {
		mut refused := false
		validate_command(input_limit) or { refused = true }
		assert refused
	}
}

fn test_command_launch_grants_only_documents_and_does_not_append_or_expand_them() {
	path := os.real_path(os.temp_dir()) + '/vinix-command-' + time.now().unix_micro().str()
	os.write_file(path, 'document')!
	defer { os.rm(path) or {} }
	key := 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
	config := Config{ architecture: 'x86_64', repositories: [Repository{ id: 'fixture', url: 'https://example.invalid', public_key: key }] }
	app := Package{ id: 'app', version: '1.0.0', architecture: 'x86_64', name: 'App', license: 'MIT', kind: 'native', entrypoint: 'bin/app',
		files: [Payload{ path: 'bin/app', bytes: 1, sha256: '01'.repeat(32), executable: true }], permissions: ['files'], arguments: ['@DATA@/fixed'] }
	state := State{ generation: 1, architecture: 'x86_64', requested: ['app'], packages: [Installed{ package: app, repository: 'fixture', public_key: key, sequence: 1 }] }
	literal := ['-i', path, '-o', 'a space; $(literal)', '@DATA@/literal', '', '--uid', '0']
	launch := command_launch_plan(config, '/var/lib/vinix-packages', state, 'app', '/home/user/data', 1000, 1000,
		CommandLaunch{ arguments: literal, documents: [path] }, false)!
	boundary := launch.arguments.index('--')
	assert launch.arguments[boundary + 1..] == ['/var/lib/vinix-packages/generations/1/apps/app/bin/app', '/home/user/data/fixed', ...literal]
	assert launch.arguments[..boundary].filter(it == path).len == 1
	assert launch.arguments[..boundary].filter(it == '/etc/passwd').len == 0
	assert launch.arguments.last() == '0'
	assert launch.directory == '/var/lib/vinix-packages/generations/1/apps/app'
	private := command_launch_plan(config, '/var/lib/vinix-packages', state, 'app', '/home/user/data', 1000, 1000,
		CommandLaunch{ arguments: literal, documents: [path], data_cwd: true }, false)!
	assert private.arguments == launch.arguments && private.directory == '/home/user/data'
	assert 'tty' !in launch.arguments[launch.arguments.index('--promises') + 1].split(' ')
	terminal := command_launch_plan(config, '/var/lib/vinix-packages', state, 'app', '/home/user/data', 1000, 1000,
		CommandLaunch{ arguments: ['/etc/passwd'] }, true)!
	assert '/etc/passwd' !in terminal.arguments[..terminal.arguments.index('--')]
	assert 'TERM=linux' in terminal.arguments
	mut revoked := false
	command_launch_plan(Config{ ...config, repositories: [] }, '/var/lib/vinix-packages', state, 'app', '/home/user/data', 1000, 1000, CommandLaunch{}, false) or { revoked = err.msg().contains('revoked') }
	assert revoked
	denied_state := State{ ...state, packages: [Installed{ ...state.packages[0], package: Package{ ...app, permissions: [] } }] }
	mut denied := false
	command_launch_plan(config, '/var/lib/vinix-packages', denied_state, 'app', '/home/user/data', 1000, 1000,
		CommandLaunch{ documents: [path] }, false) or { denied = err.msg().contains('file permission') }
	assert denied
}

fn test_command_session_reconstructs_literal_prefix_and_rechecks_limits() {
	input := LaunchInput{ documents: ['/home/alex/a space'], arguments: ['', '--file', '$(literal)', '@DATA@/literal'], command: true, terminal: true }
	launch := launch_session_request(Config{ architecture: 'aarch64', launch_user: 'alex' }, '/usr/bin/vinix-package', 'app', input)!
	assert launch.arguments == ['run', '--isolated', 'alex', '/usr/bin/vinix-package', 'run-terminal-args', 'app', '--file', '/home/alex/a space', '--', '', '--file', '$(literal)', '@DATA@/literal']
	private := launch_session_request(Config{ architecture: 'aarch64', launch_user: 'alex' }, '/usr/bin/vinix-package', 'app', LaunchInput{ ...input, data_cwd: true })!
	assert private.arguments == ['run', '--isolated', 'alex', '/usr/bin/vinix-package', 'run-terminal-args', 'app', '--data-cwd', '--file', '/home/alex/a space', '--', '', '--file', '$(literal)', '@DATA@/literal']
	mut refused := false
	launch_session_request(Config{ architecture: 'aarch64', launch_user: 'alex' }, '/usr/bin/vinix-package', 'app', LaunchInput{ command: true, arguments: ['nul\x00'] }) or { refused = true }
	assert refused
}
