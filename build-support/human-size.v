// SPDX-License-Identifier: GPL-2.0-or-later
module main

import imagehost
import os

fn main() {
	if os.args.len != 2 {
		eprintln('Usage: human-size BYTES')
		exit(2)
	}
	println(imagehost.human_size(os.args[1]) or {
		eprintln(err)
		exit(2)
	})
}
