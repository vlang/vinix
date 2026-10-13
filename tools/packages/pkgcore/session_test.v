// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

fn test_root_launch_uses_only_explicit_account_and_literal_arguments() {
	config := Config{ architecture: 'aarch64', launch_user: 'alex' }
	launch := launch_session(config, '/usr/bin/vinix-package', 'editor', ['/home/alex/a space; \$literal.txt'])!
	assert launch.program == '/usr/sbin/vinix-session'
	assert launch.arguments == ['run', '--isolated', 'alex', '/usr/bin/vinix-package', 'run', 'editor',
		'/home/alex/a space; \$literal.txt']
	assert launch.directory == '/'
	terminal := launch_session_mode(config, '/usr/bin/vinix-package', 'editor', ['/home/alex/a space; \$literal.txt'], true)!
	assert terminal.arguments == ['run', '--isolated', 'alex', '/usr/bin/vinix-package', 'run-terminal', 'editor', '/home/alex/a space; \$literal.txt']
	for bad in ['', 'root', 'greeter', 'nobody', 'user;cmd', '../user', 'user.name', '-user'] {
		mut denied := false
		launch_session(Config{ architecture: 'aarch64', launch_user: bad }, '/usr/bin/vinix-package', 'editor', []) or { denied = true }
		assert denied
	}
	for path in ['relative', '/home/alex/new\nline', '/home/alex/nul\x00'] {
		mut denied := false
		launch_session(config, '/usr/bin/vinix-package', 'editor', [path]) or { denied = true }
		assert denied
	}
}
