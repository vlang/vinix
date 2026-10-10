// SPDX-License-Identifier: GPL-2.0-or-later
module main

import imagepatch
import os

fn main() {
	if os.args.len != 2 {
		eprintln('usage: ${os.args[0]} IMAGE')
		exit(2)
	}
	imagepatch.root_owner(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
}
