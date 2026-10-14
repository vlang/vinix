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
	for name, arguments in {
		'pack-source-check': ['/tmp/pack-source-contract']
		'pack-source-core': []string{}
	} {
		mut child := os.new_process('/usr/share/package-fixtures/' + name)
		child.set_args(arguments)
		child.set_redirect_stdio_merged()
		child.run()
		output := child.stdout_slurp()
		child.wait(); code := child.code; child.close()
		print(output)
		if code != 0 { return error('${name} failed (${code})') }
	}
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-pack-source')
	mut passed := true
	check() or { eprintln(err); passed = false }
	if passed {
		println('PACKAGE PACK SOURCE captured-tree bounded-work checked-mode canonical-retry PASS')
		println('HWTEST PASS packages-pack-source')
	} else { println('HWTEST FAIL packages-pack-source') }
	C.sync()
	C.reboot(0x4321fedc)
	for { C.usleep(1_000_000) }
}
