// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import hosttest

fn main() {
	args := hosttest.parse_arguments(os.args[1..], [
		hosttest.Option{'--arch', true, ['amd64', 'arm64']},
		hosttest.Option{'--host', false, []string{}},
		hosttest.Option{'--implementations-only', false, []string{}},
	], 1, 'Usage: compile_primitives.v OUTPUT [--arch amd64|arm64] [--host] [--implementations-only]',
		'Compile the native V module which directly binds upstream header primitives.') or { eprintln(err.msg()); exit(2) }
	arch := args.options['--arch'] or { 'amd64' }
	output := hosttest.resolve_path(if args.positional[0] == '' { '.' } else { args.positional[0] }) or { eprintln(err.msg()); exit(1) }
	hosttest.generate_header_primitives(output, arch, '--host' in args.options, '--implementations-only' in args.options) or { eprintln(err.msg()); exit(1) }
}
