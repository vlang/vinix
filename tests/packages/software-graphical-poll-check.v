// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the actual guest polling function with the same manual-free compiler.
module main

import crypto.sha256
import os

fn invoke(program string, arguments []string) ! {
	mut child := os.new_process(program)
	defer { child.close() }
	child.set_args(arguments)
	child.run()
	child.wait()
	if child.code != 0 { return error(program + ' failed') }
}

fn run() ! {
	root := os.dir(os.dir(os.dir(os.real_path(@FILE))))
	work := root + '/build/software-graphical-poll-check'
	os.mkdir_all(work + '/proc/123')!
	source := os.read_file(root + '/tests/packages/software-graphical-guest/main.v')!
	function := source.all_after('fn counter_child_present() !bool {').all_before('\nfn wait_counter_closed(')
	if function == source || !function.contains('entries.free()') {
		return error('guest polling function was not found')
	}
	// Only the procfs location changes. Compile the actual function body so the
	// sanitizer covers its generated typed-array/string cleanup on every exit.
	quoted := "'" + (work + '/proc').replace('\\', '\\\\').replace("'", "\\'") + "'"
	staged := 'module main\nimport os\nconst fixture_proc = ' + quoted + '\n' +
		'fn counter_child_present() !bool {' + function.replace("'/proc'", 'fixture_proc').replace("'/proc/'", "fixture_proc + '/'") +
		r'
fn main() {
 path := fixture_proc + "/123/cmdline"
 for _ in 0 .. 1000 {
  os.write_file(path, "/usr/bin/vinix-package\x00run-window\x00org.vinix.counter\x00")!
  assert counter_child_present()!
  os.write_file(path, "/var/lib/vinix-packages/generations/1/apps/org.vinix.counter/bin/counter\x00")!
  assert counter_child_present()!
  os.write_file(path, "/usr/bin/unrelated\x00")!
  assert !counter_child_present()!
  os.rm(path)!
  assert !counter_child_present()!
 }
 println("SOFTWARE GRAPHICAL POLL 4000 scans; helper, child, unrelated and disappearing process PASS")
}
'
	os.write_file(work + '/poll.v', staged)!
	v := os.getenv('V')
	if v == '' { return error('set V to the reviewed compiler') }
	invoke(v, ['-new-compiler', '-nocache', '-gc', 'none', '-manualfree', '-cc', 'clang',
		'-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
		'-ldflags', '-fsanitize=address,undefined', '-o', work + '/poll', work + '/poll.v'])!
	invoke(work + '/poll', [])!
	println('guest-main-sha256 ' + sha256.sum(source.bytes()).hex())
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
