// SPDX-License-Identifier: GPL-2.0-or-later
// Uncompiled entry for a future independently copied, qualified module.
module main

import compactproof
import os

fn main() {
	if os.args.len != 3 || os.args[1] != '--controls' {
		eprintln('use --controls NEW_EXTERNAL_OUTPUT')
		exit(2)
	}
	compactproof.run_current_controls(os.args[2]) or { eprintln(err); exit(1) }
}
