// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import os
import sourcecommand

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 2 {
		eprintln('expected hosted launcher path')
		exit(2)
	}
	result := sourcecommand.capture_full([os.args[1]], os.environ(), 20, 1024 * 1024, cachecli.cancelled) or {
		eprintln(err)
		exit(1)
	}
	print(result.stdout)
	eprint(result.stderr)
	exit(if cachecli.cancelled() {
		cachecli.interrupt_status()
	} else if result.status == 0 {
		0
	} else {
		1
	})
}
