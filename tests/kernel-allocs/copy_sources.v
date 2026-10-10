// SPDX-License-Identifier: GPL-2.0-or-later
module main

import copycore
import os

fn main() {
	if os.args.len != 4 {
		eprintln('Usage: copy-sources KERNEL FILES DESTINATION')
		exit(2)
	}
	files := copycore.copy_sources(os.args[1], os.args[2], os.args[3]) or {
		eprintln(err)
		exit(1)
	}
	for file in files {
		println(file)
	}
}
