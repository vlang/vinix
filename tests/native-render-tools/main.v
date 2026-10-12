// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import os
import renderhost

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len < 2 {
		eprintln('expected native render command')
		exit(2)
	}
	status := renderhost.dispatch(os.real_path(os.dir(@FILE) + '/../..'), os.args[1], os.args[2..]) or {
		eprintln(err)
		exit(if cachecli.cancelled() {
			cachecli.interrupt_status()
		} else if err.code() == 2 {
			2
		} else if err.code() in [130, 143] {
			err.code()
		} else {
			1
		})
	}
	exit(if cachecli.cancelled() { cachecli.interrupt_status() } else { status })
}
