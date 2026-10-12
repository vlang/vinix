// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import kpihost
import os

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 2 { exit(2) }
	kpihost.native_recipe_cases(os.real_path(os.dir(@FILE) + '/../..'), os.args[1]) or {
		eprintln(err)
		exit(1)
	}
}
