// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import os
import sourcecommand

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	root := os.real_path(os.dir(@FILE) + '/../..')
	mut argv := [root + '/build-support/build-validation-guest', '--source',
		root + '/tests/native-launcher-tools/guest.v', '--define', 'tarstream_fd_only']
	for path in ['tests/native-launcher-tools/steamshim', 'build-support/tarstream',
		'build-support/tarcore', 'tests/desktop-perf/perfreport'] {
		argv << ['--source-input', root + '/' + path]
	}
	argv << os.args[1..]
	argv << ['--include-dir', root + '/tests/native-launcher-tools/steamshim']
	result := sourcecommand.capture_full(argv, os.environ(), -1, 64 * 1024 * 1024, cachecli.cancelled) or {
		eprintln(err)
		exit(1)
	}
	print(result.stdout)
	eprint(result.stderr)
	exit(if cachecli.cancelled() { cachecli.interrupt_status() } else { result.status })
}
