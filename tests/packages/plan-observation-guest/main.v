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
	if code != 0 || (marker != '' && !text.contains(marker)) { return error('native plan observation fixture failed: ' + path) }
}

fn check() ! {
	child('/usr/share/package-fixtures/plan', 'PLAN OBSERVATION 33-package nested copies')!
	child('/usr/share/package-fixtures/preference', 'Resolver preference: 1000 public successful')!
	child('/usr/share/package-fixtures/service', '')!
	child('/usr/share/package-fixtures/empty', '')!
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }; fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-plan-observation')
	mut passed := true; check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-plan-observation' } else { 'HWTEST FAIL packages-plan-observation' })
	C.sync(); C.reboot(0x4321fedc); for { C.sleep(1) }
}
