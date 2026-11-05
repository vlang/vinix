// SPDX-License-Identifier: GPL-2.0-or-later
module main

import compactui
import os

fn main() {
	if os.args.len != 3 || os.args[1] != '--controls' {
		eprintln('requires --controls NEW_EXTERNAL_OUTPUT')
		exit(2)
	}
	compactui.run_controls(os.args[2]) or { eprintln(err); exit(1) }
}
