// SPDX-License-Identifier: GPL-2.0-or-later
// Produce an explicitly instrumented copy for isolated race qualification.
// The ordinary kernel never includes this scheduling window.
module main

import os

fn run() ! {
	if os.args.len != 3 { return error('Usage: duppublish-instrument.v INPUT-FILE OUTPUT-FILE') }
	source := os.read_file(os.args[1])!
	anchor := '\tnew_fdnum := fdnum_create_from_fd(new_process, new_fd, newfdnum, specific) or {\n\t\tnew_fd.unref()\n\t\treturn none\n\t}\n'
	if source.count(anchor) != 1 || source.contains('dup publication qualification window') || source.contains('import sched\n') { return error('unexpected descriptor duplication source') }
	window := '\n\t// dup publication qualification window: only scalar state after insertion.\n\tif new_fdnum == 63 {\n\t\tfor _ in 0 .. 32 { sched.reschedule() }\n\t}\n'
	if source.count('import proc\n') != 1 { return error('unexpected imports') }
	if os.exists(os.args[2]) { return error('output must be fresh') }
	os.write_file(os.args[2], source.replace('import proc\n', 'import proc\nimport sched\n').replace(anchor, anchor + window))!
	println('Descriptor publication scheduling window: generated')
}
fn main() { run() or { eprintln(err.msg()); exit(1) } }
