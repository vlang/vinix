// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hostfixturebuild
import hosttest
import os

fn main() {
	args := hosttest.parse_arguments(os.args[1..], [
		hosttest.Option{'--arch', true, ['amd64', 'arm64']},
		hosttest.Option{'--no-model', false, []string{}},
	], 2, 'Usage: compile_host.v SOURCE OUTPUT [--arch amd64|arm64] [--no-model]',
		'Stage an independent V host fixture with shared native model declarations.') or { eprintln(err.msg()); exit(2) }
	source := hosttest.module_resolve(if args.positional[0] == '' { '.' } else { args.positional[0] }) or { eprintln(err.msg()); exit(1) }
	output := hosttest.module_resolve(if args.positional[1] == '' { '.' } else { args.positional[1] }) or { eprintln(err.msg()); exit(1) }
	result := hostfixturebuild.generate(source, output, args.options['--arch'] or { 'arm64' }, '--no-model' !in args.options) or { eprintln(err.msg()); exit(1) }
	print(result.stdout)
	eprint(result.stderr)
}
