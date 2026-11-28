// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn section(source string, start string, end string) string {
	a := source.index(start) or { panic(start) }
	b := source[a..].index(end) or { panic(end) }
	return source[a..a + b]
}

fn main() {
	root := os.real_path(os.join_path(os.dir(@FILE), '..', '..'))
	tmp := os.getenv('TMPDIR')
	work := os.join_path(if tmp != '' { tmp } else { os.temp_dir() }, 'vinix-xhci-recovery-${os.getpid()}')
	os.mkdir_all(work) or { panic(err) }
	defer { os.rmdir_all(work) or {} }
	core := os.read_file(os.join_path(root, 'kernel/dev/xhci/xhci.v')) or { panic(err) }
	hid := os.read_file(os.join_path(root, 'kernel/dev/xhci/hid.v')) or { panic(err) }
	// Use actual production types, constants, ring publication and event
	// decoding as well as recovery.v; only hardware and HID sinks are fake.
	support := 'module xhci\n' + section(core, '// TRB types.', '// Operational registers.') +
		section(core, '// One page of 16-byte', '__global (') +
		section(hid, 'const kind_keyboard', '__global (') +
		section(core, 'fn new_ring()', '// The next event') +
		section(core, 'fn control(', 'fn ctx(') +
		section(hid, 'const modifier_codes', '// An interface') +
		section(hid, 'fn keycode(', 'fn (mut f HidFunction) keyboard_report') +
		hid[hid.index('fn forget_function_keys(') or { panic('helper') }..]
	os.write_file(os.join_path(work, 'support.v'), support) or { panic(err) }
	for source in ['kernel/dev/xhci/recovery.v', 'tests/xhci-recovery/fixture/core_test.v'] {
		os.cp(os.join_path(root, source), os.join_path(work, os.file_name(source))) or { panic(err) }
	}
	mut compiler := os.getenv('V')
	if compiler == '' { compiler = @VEXE }
	mut process := os.new_process(compiler)
	process.set_args(['-enable-globals', '-cc', 'cc', 'test', work])
	process.set_redirect_stdio()
	process.run()
	process.wait()
	print(process.stdout_slurp())
	eprint(process.stderr_slurp())
	code := process.code
	process.close()
	if code != 0 { exit(code) }
}
