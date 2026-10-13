// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import graphicsbuild
import os

fn run(args []string) ! {
	if args.len == 0 || args[0] in ['-h', '--help'] {
		println('Usage: graphics-tools checksum blake2b|sha512 FILE EXPECTED LABEL\n       graphics-tools venus-prepare ARCHIVE BUILD MANIFEST\n       graphics-tools libraries SOURCE DESTINATION')
		return
	}
	match args[0] {
		'checksum' {
			if args.len != 5 { return error('checksum requires ALGORITHM FILE EXPECTED LABEL') }
			graphicsbuild.verify(args[1], args[2], args[3], args[4])!
		}
		'venus-prepare' {
			if args.len != 4 { return error('venus-prepare requires ARCHIVE BUILD MANIFEST') }
			graphicsbuild.prepare(args[1], args[2], args[3], graphicsbuild.Options{})!
		}
		'libraries' {
			if args.len != 3 { return error('libraries requires SOURCE DESTINATION') }
			graphicsbuild.libraries(args[1], args[2])!
		}
		else { return error('unknown graphics-tools operation: ' + args[0]) }
	}
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	run(os.args[1..]) or {
		eprintln(err.msg())
		exit(if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 })
	}
}
