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
	// Each no-collector assertion case has the same process lifetime as a
	// publisher CLI command; repeated signing does not accumulate across cases.
	for name in ['writers', 'admission', 'containment', 'entries', 'retirement'] {
		mut child := os.new_process('/usr/share/package-fixtures/publisher-workspace-core')
		child.set_args(['case', name])
		child.set_redirect_stdio_merged()
		child.run()
		output := child.stdout_slurp()
		child.wait(); code := child.code; child.close()
		print(output)
		if code != 0 { return error('${name} failed (${code})') }
		println('PUBLISHER WORKSPACE CASE ' + name + ' PASS')
	}
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-publisher-workspace')
	mut passed := true
	check() or { eprintln(err); passed = false }
	if passed {
		println('PACKAGE PUBLISHER WORKSPACE common-lock confined-output safe-admission recovery PASS')
		println('HWTEST PASS packages-publisher-workspace')
	} else { println('HWTEST FAIL packages-publisher-workspace') }
	C.sync()
	C.reboot(0x4321fedc)
	for { C.usleep(1_000_000) }
}
