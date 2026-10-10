// SPDX-License-Identifier: GPL-2.0-or-later
module main

import boundarycheck
import hosttest
import os

fn main() {
	if os.args[1..] == ['--help'] || os.args[1..] == ['-h'] {
		println('Usage: tests/native-boundaries/run\nCompare frozen C headers and production V on an ARM64 host using Clang ASan/UBSan.')
		return
	}
	if os.args.len != 1 {
		eprintln('Usage: tests/native-boundaries/run')
		exit(2)
	}
	output := boundarycheck.compare(hosttest.root(), os.uname().machine, os.environ()) or {
		eprintln(err.msg())
		exit(1)
	}
	print(output)
}
