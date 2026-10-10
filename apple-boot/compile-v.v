// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hostcompiler
import hosttest
import os

fn main() {
	args := hosttest.parse_arguments(os.args[1..], [hosttest.Option{'--host', false, []string{}}],
		1, 'Usage: compile-v OUTPUT [--host]',
		'Generate the freestanding loader object source from maintained V modules.') or {
		eprintln(err)
		exit(2)
	}
	hostcompiler.generate(args.positional[0], '--host' in args.options) or {
		eprintln(err)
		exit(1)
	}
}
