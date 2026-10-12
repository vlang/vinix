// SPDX-License-Identifier: GPL-2.0-or-later
// Manual cross links must compile the selected V compiler's external runtime.
module main

import os

fn main() {
	if os.args.len != 2 {
		eprintln('Usage: stage-v-runtime.v OUTPUT_DIRECTORY')
		exit(2)
	}
	output := os.abs_path(os.args[1])
	os.mkdir_all(output) or { panic(err) }
	builtin := os.join_path(@VEXEROOT, 'vlib', 'builtin')
	source := builtin + '/segfault_handler_nix.c'
	if os.is_file(source) {
		for name in ['segfault_handler_nix.c', 'segfault_handler_nix.h'] {
			os.cp(builtin + '/' + name, output + '/' + name) or { panic(err) }
		}
	} else {
		// Older compilers emitted this runtime inline in the generated program.
		os.write_file(output + '/segfault_handler_nix.c', '// Runtime emitted inline by the selected V compiler.\n') or { panic(err) }
	}
}
