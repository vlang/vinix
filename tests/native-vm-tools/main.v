// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import os
import vmhost

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len < 2 { exit(2) }
	root := os.real_path(os.dir(@FILE) + '/../..')
	status := vmhost.dispatch(root, os.args[1], os.args[2..]) or {
		eprintln(err)
		exit(if cachecli.cancelled() {
			cachecli.interrupt_status()
		} else if err.code() == 2 {
			2
		} else {
			1
		})
	}
	exit(status)
}
