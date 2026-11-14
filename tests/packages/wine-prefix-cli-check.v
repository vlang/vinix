// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn refused(cli string, args []string, message string) ! {
	mut child := os.new_process(cli)
	defer { child.close() }
	child.set_args(args)
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	if child.code != 1 || !output.contains(message) { return error('unexpected CLI refusal: ' + output) }
}

fn run() ! {
	if os.args.len != 2 { return error('usage: wine-prefix-cli-check COMPILED_VINIX_PACKAGE') }
	cli := os.args[1]
	for command in ['wine-prefix-review', 'wine-prefix-additions'] {
		refused(cli, [command], 'requires an installed application ID')!
		refused(cli, [command, 'app', '/tmp/private', 'extra'], 'requires an installed application ID')!
		refused(cli, ['--root', '/tmp/alternate', command, 'app', '/tmp/private'], 'requires the real root')!
		refused(cli, ['--root', '/', command, 'app', '/tmp/private'], 'requires the real root')!
		refused(cli, ['--offline', command, 'app', '/tmp/private'], 'requires the real root')!
		refused(cli, [command, '../app', '/tmp/private'], 'requires a valid application ID')!
		refused(cli, [command, 'app', 'relative'], 'requires a valid application ID')!
		refused(cli, ['--progress', command, 'app', '/tmp/private'], '--progress supports')!
	}
	println('Wine installed-prefix CLI refusal controls PASS (no installed-state success claimed)')
}

fn main() { run() or { eprintln(err); exit(1) } }
