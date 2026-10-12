// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import androidrunfixtures
import hosttest
import os

fn main() {
	status := androidrunfixtures.roblox_tests(hosttest.root(), os.args[1..]) or {
		eprintln(err)
		exit(1)
	}
	exit(status)
}
