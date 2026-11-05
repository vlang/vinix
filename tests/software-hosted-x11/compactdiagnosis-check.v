// SPDX-License-Identifier: GPL-2.0-or-later
module main

import compactdiagnosis
import os

fn main() {
	if os.args.len != 3 || os.args[1] != '--controls' { eprintln('use --controls NEW-EXTERNAL-DIRECTORY'); exit(1) }
	compactdiagnosis.controls(os.args[2]) or { eprintln(err); exit(1) }
}
