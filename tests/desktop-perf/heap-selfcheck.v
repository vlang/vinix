// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import perfheap

fn main() {
	if os.args.len != 2 { eprintln('usage: heap-selfcheck FRESH_STATE'); exit(1) }
	count := perfheap.selfcheck(os.args[1]) or { eprintln(err); exit(1) }
	println('PERF HEAP explicit parser/reader controls PASS ' + count.str())
}
