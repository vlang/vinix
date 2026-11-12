// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import releaseasset

fn main() {
	if os.args.len != 4 {
		eprintln('Usage: stage-release-runtime.v SOURCE OUTPUT SHA256')
		exit(2)
	}
	releaseasset.stage(os.args[1], os.args[2], os.args[3]) or {
		eprintln(err)
		exit(1)
	}
	println('Staged verified static ARM64 iOS release runtime')
}
