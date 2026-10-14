// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <fcntl.h>
#include <sys/reboot.h>
#include <unistd.h>
fn C.dup2(int, int) int
fn C.sync()
fn C.reboot(int) int
fn C.usleep(u32) int

fn check() ! {
	for name in ['state-preflight-core', 'state-preflight-probe'] {
		mut child := os.new_process('/usr/share/package-fixtures/' + name)
		if name == 'state-preflight-probe' { child.set_args(['/tmp/state-preflight']) }
		child.set_redirect_stdio_merged(); child.run()
		output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
		print(output)
		if code != 0 || output.contains(': fn test_') { return error('${name} failed (${code})') }
		println('STATE PROCESS ' + name + ' PASS')
	}
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-state-preflight')
	mut passed := true
	check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-state-preflight' } else { 'HWTEST FAIL packages-state-preflight' })
	C.sync(); C.reboot(0x4321fedc)
	for { C.usleep(1_000_000) }
}
