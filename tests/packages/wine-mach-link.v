// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tests.packages.winemacholink

fn run() ! {
	if os.args.len == 4 && os.args[1] == 'build' {
		winemacholink.build(os.args[2], os.args[3])!
	} else if os.args.len == 3 && os.args[1] == 'check' {
		winemacholink.admit(os.abs_path(os.args[2]))!
	} else { return error('usage: MACH_LINK build HOST_C_DIRECTORY FRESH_OUTPUT | check CAPTURE') }
	println('WINE MACH-O CAPTURED LINK PASS')
}

fn main() { run() or { eprintln(err); exit(1) } }
