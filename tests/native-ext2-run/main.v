// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import os
import xtcontroller

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	root := os.real_path(os.dir(@FILE) + '/../..')
	options := xtcontroller.options(root, os.args[1..]) or {
		eprintln(err)
		exit(2)
	}
	xtcontroller.run(root, options) or {
		eprintln(err)
		exit(if cachecli.cancelled() {
			cachecli.interrupt_status()
		} else if err.code() == 2 {
			2
		} else {
			1
		})
	}
}
