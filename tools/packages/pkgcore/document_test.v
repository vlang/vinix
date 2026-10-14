// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import net.unix
import os
import time

fn C.mkfifo(&char, u32) int

fn test_document_grants_require_regular_targets_in_every_launch_mode() {
	work := os.real_path(os.temp_dir()) + '/vdoc-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/directory')!
	defer { os.rmdir_all(work) or { panic(err) } }
	os.write_file(work + '/regular with spaces', 'document')!
	os.symlink('regular with spaces', work + '/alias')!
	os.symlink('missing', work + '/dangling')!
	os.symlink('cycle', work + '/cycle')!
	assert C.mkfifo((work + '/fifo').str, 0o600) == 0
	mut socket := unix.listen_stream(work + '/socket', unix.ListenOptions{})!
	defer { socket.close() or {} }
	for name in ['fifo', 'socket', 'directory'] { os.symlink(name, work + '/' + name + '-alias')! }
	os.symlink('/dev/null', work + '/device-alias')!
	for architecture in ['aarch64', 'x86_64'] {
		key := 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
		config := Config{ architecture: architecture, repositories: [Repository{ id: 'fixture', url: 'https://example.invalid', public_key: key }] }
		app := Package{ id: 'app', version: '1.0.0', architecture: architecture, name: 'App', license: 'MIT', kind: 'native', entrypoint: 'bin/app',
			files: [Payload{ path: 'bin/app', bytes: 1, sha256: key, executable: true }], window_protocol: 1, permissions: ['display', 'files'] }
		state := State{ generation: 1, architecture: architecture, requested: ['app'], packages: [Installed{ package: app, repository: 'fixture', public_key: key, sequence: 1 }] }
		for input in [LaunchInput{}, LaunchInput{ terminal: true }, LaunchInput{ window: true },
			LaunchInput{ command: true, arguments: ['literal'] }, LaunchInput{ command: true, terminal: true, arguments: ['literal'] }] {
			for name in ['regular with spaces', 'alias'] {
				path := work + '/' + name
				launch := application_launch_plan(config, '/var/lib/vinix-packages', state, 'app', '/home/user/data', 1000, 1000,
					LaunchInput{ ...input, documents: [path] })!
				boundary := launch.arguments.index('--')
				grant := launch.arguments.index(path)
				assert grant > 0 && grant < boundary && launch.arguments[grant - 1] == '--unveil' && launch.arguments[grant + 1] == 'rw'
				assert launch.arguments[boundary + 2..] == if input.command { ['literal'] } else { [path] }
			}
			for path in [work + '/fifo', work + '/socket', work + '/directory', work + '/missing', work + '/dangling', work + '/cycle',
				work + '/fifo-alias', work + '/socket-alias', work + '/directory-alias', work + '/device-alias', '/dev/null'] {
				mut refused := false
				application_launch_plan(config, '/var/lib/vinix-packages', state, 'app', '/home/user/data', 1000, 1000,
					LaunchInput{ ...input, documents: [path] }) or {
					refused = err.msg() == 'document must be an existing absolute regular file: ' + path
				}
				assert refused, path
			}
		}
	}
}
