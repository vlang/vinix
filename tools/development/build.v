// SPDX-License-Identifier: GPL-2.0-or-later
module main

import devcore
import os

fn main() {
	args := os.args[1..]
	if args.len == 2 && args[0] == 'hash' {
		hash := if os.is_dir(args[1]) {
			devcore.tree_hash(args[1])!
		} else {
			devcore.file_hash(args[1])!
		}
		println(hash)
		return
	}
	if args.len != 3 || args[0] != 'build' {
		println('Usage: vinix-build hash PATH | build PLAN.json FRESH-OUTPUT-DIRECTORY')
		exit(if args in [['--help'], []string{}] { 0 } else { 2 })
	}
	devcore.build(os.read_file(args[1])!, args[2]) or {
		eprintln(err)
		exit(1)
	}
}
