// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import ioshost
import os

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	options := ioshost.parse(os.args[1..]) or {
		eprintln(err)
		exit(2)
	}
	tools := ioshost.Tools{ root: os.real_path(os.dir(@FILE) + '/../..'), environment: os.environ() }
	exit(tools.run(options) or {
		eprintln(err)
		if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 }
	})
}
