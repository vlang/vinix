// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <fcntl.h>
#include <sys/reboot.h>
#include <unistd.h>
fn C.dup2(int, int) int
fn C.sync()
fn C.reboot(int) int
fn C.sleep(u32) u32

fn child(path string, marker string) ! {
	mut process := os.new_process(path); process.set_redirect_stdio_merged()
	process.run(); text := process.stdout_slurp(); process.wait(); code := process.code; process.close(); print(text)
	if code != 0 || !text.contains(marker) { return error('native Software provenance fixture failed: ' + path) }
}

fn check() ! {
	child('/usr/share/package-fixtures/view', 'SOFTWARE PROVENANCE both hosts')!
	child('/usr/share/package-fixtures/protocol', 'SOFTWARE PROVENANCE protocol')!
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }; fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-software-provenance')
	mut passed := true; check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-software-provenance' } else { 'HWTEST FAIL packages-software-provenance' })
	C.sync(); C.reboot(0x4321fedc); for { C.sleep(1) }
}
