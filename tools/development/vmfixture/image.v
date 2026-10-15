// SPDX-License-Identifier: GPL-2.0-or-later
// Test-only qemu-img delegate: inject one failure before or after a real command.
module main

import os

fn main() {
	root := os.dir(os.executable())
	real_tool := os.read_file(root + '/image-tool.path') or { panic(err) }
	args := os.args[1..]
	if args.len == 0 { exit(2) }
	operation := if args[0] == 'snapshot' && args.len > 3 { args[3] } else { args[0] }
	fault := os.read_file(root + '/image-tool.fault') or { '' }
	injected := fault in ['before:' + operation, 'after:' + operation]
	if injected { os.rm(root + '/image-tool.fault') or { panic(err) } }
	if fault == 'before:' + operation {
		eprintln('injected failure before ${operation}')
		exit(73)
	}
	mut child := os.new_process(real_tool)
	child.set_args(args)
	child.run()
	child.wait()
	status := child.code
	child.close()
	if status == 0 && fault == 'after:' + operation {
		eprintln('injected failure after ${operation}')
		exit(73)
	}
	exit(status)
}
