// SPDX-License-Identifier: GPL-2.0-or-later
// Test-only startup barrier before replacing this owned child with real QEMU.
module main

import os
import time

fn main() {
	root := os.dir(os.executable())
	os.write_file(root + '/emulator.ready', 'waiting') or { panic(err) }
	deadline := time.sys_mono_now() + u64(30 * time.second)
	for !os.exists(root + '/emulator.release') {
		if time.sys_mono_now() >= deadline { eprintln('emulator fixture deadline expired'); exit(1) }
		time.sleep(10 * time.millisecond)
	}
	if os.exists(root + '/emulator.fail') { exit(73) }
	real_tool := os.read_file(root + '/emulator.path') or { panic(err) }
	os.execvp(real_tool, os.args[1..]) or { panic(err) }
}
