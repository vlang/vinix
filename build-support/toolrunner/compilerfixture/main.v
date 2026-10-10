// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn main() {
	if os.args.len == 2 && os.args[1] == 'version' {
		println('V 0.5.2 fixture')
		return
	}
	index := os.args.index('-o')
	if index >= 0 {
		println('compiler stdout marker')
		eprintln('compiler stderr marker')
		status := os.getenv('VINIX_TOOL_TEST_COMPILE_STATUS').int()
		if status != 0 { exit(status) }
		os.cp(os.executable(), os.args[index + 1]) or { panic(err) }
		os.chmod(os.args[index + 1], 0o755) or { panic(err) }
		return
	}
	println('tool output')
	println('cwd: ' + os.getwd())
	for arg in os.args[1..] { println('arg: ' + arg) }
	exit(os.getenv('VINIX_TOOL_TEST_EXIT_STATUS').int())
}
