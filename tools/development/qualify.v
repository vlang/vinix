// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import qualcore

fn main() {
	mut args := os.args[1..].clone()
	if args.len == 0 || args == ['--help'] {
		println('Usage: vinix-qualify [--require-vinix] FRESH-OUTPUT [c,cpp,v,node,typescript,rust,cargo,go,java,make,cmake,ninja,npm,gdb,sqlite]')
		return
	}
	require := args[0] == '--require-vinix'
	if require { args.delete(0) }
	if args.len !in [1, 2] {
		eprintln('invalid arguments')
		exit(2)
	}
	profiles := if args.len == 1 { qualcore.catalog } else { args[1].split(',') }
	report := qualcore.qualify(profiles, args[0], require) or {
		eprintln(err)
		exit(1)
	}
	if !report.all_selected_passed { exit(1) }
}
