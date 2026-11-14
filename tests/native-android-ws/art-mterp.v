// SPDX-License-Identifier: GPL-2.0-or-later
// Prepared interpreter-generator port. Compilation and checks are pending;
// see maps-art-mterp-20261114.md. Not integrated into the native ART build.
module main

import artmterp
import os

fn main() {
	if os.args.len == 3 && os.args[1] == '--self-test' {
		artmterp.check_mterp(os.abs_path(os.args[2])) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len < 3 {
		eprintln('usage: art-mterp OPCODE_HEADER TEMPLATE... | --self-test FRESH_ROOT')
		exit(2)
	}
	input := os.read_file(os.args[1]) or { eprintln(err); exit(1) }
	output := artmterp.mterp(input, os.args[2..]) or { eprintln(err); exit(1) }
	print(output)
}
