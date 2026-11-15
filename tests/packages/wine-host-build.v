// SPDX-License-Identifier: GPL-2.0-or-later
// Selected host V/C build profile; complete Mach-O link closure remains open.
module main

import os
import tests.packages.winehostbuild
import tests.packages.winesdkdeny

fn main() {
	winehostbuild.verify_self() or { eprintln(err); exit(1) }
	if os.args.len >= 2 && os.args[1] == 'sdk-replay-child' {
		winesdkdeny.child() or { eprintln(err); exit(1) }
		return
	}
	if os.args.len == 3 && os.args[1] == 'check' {
		winehostbuild.admit(os.real_path(os.args[2])) or { eprintln(err); exit(1) }
		println('WINE HOST BUILD ADMISSION PASS')
		return
	}
	if os.args.len != 5 || os.args[1] != 'build' {
		eprintln('usage: HOST_BUILD build ROLE V FRESH_OUTPUT | check BUILD')
		exit(1)
	}
	winehostbuild.build(os.args[2], os.args[3], os.args[4]) or { eprintln(err); exit(1) }
}
