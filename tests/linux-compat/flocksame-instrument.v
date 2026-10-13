// SPDX-License-Identifier: GPL-2.0-or-later
// Produce a private scheduling-window copy for isolated flock qualification.
module main
import os

fn run() ! {
	if os.args.len != 3 { return error('Usage: flocksame-instrument.v INPUT OUTPUT') }
	source := os.read_file(os.args[1])!
	anchor := '\trelease_description_locks(handle, true)\n'
	if source.count(anchor) != 1 || source.contains('flock conversion qualification window') || source.contains('import sched\n') || source.count('import proc\n') != 1 { return error('unexpected flock source') }
	if os.exists(os.args[2]) { return error('output must be fresh') }
	window := '\t// flock conversion qualification window: no table lock is held here.\n\tif operation & lock_nb != 0 {\n\t\tfor _ in 0 .. 32 { sched.reschedule() }\n\t}\n'
	os.write_file(os.args[2], source.replace('import proc\n', 'import proc\nimport sched\n').replace(anchor, anchor + window))!
	println('Flock conversion scheduling window: generated')
}
fn main() { run() or { eprintln(err.msg()); exit(1) } }
