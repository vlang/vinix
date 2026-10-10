// SPDX-License-Identifier: GPL-2.0-or-later
module main

import imagepatch
import os

fn main() {
	if os.args.len == 2 && os.args[1] in ['-h', '--help'] {
		println('Usage: patch-elf-interpreter BINARY OLD NEW')
		println('Replace an ELF interpreter with an equal-or-shorter absolute path.')
		return
	}
	if os.args.len != 4 {
		eprintln('Usage: patch-elf-interpreter BINARY OLD NEW')
		exit(2)
	}
	imagepatch.interpreter_file(os.args[1], os.args[2], os.args[3]) or {
		eprintln(err)
		exit(if err.msg().starts_with('the replacement') || err.msg().starts_with('expected one') {
			2
		} else {
			1
		})
	}
}
