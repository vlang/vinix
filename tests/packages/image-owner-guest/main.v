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

fn child(name string, arguments []string) ! {
	mut process := os.new_process('/usr/share/package-fixtures/' + name)
	process.set_args(arguments); process.set_redirect_stdio_merged()
	process.run(); text := process.stdout_slurp(); process.wait(); code := process.code; process.close(); print(text)
	if code != 0 || text.contains(': fn test_') { return error(name + ' failed (' + code.str() + ')') }
	println('IMAGE OWNER PROCESS ' + name + ' ' + arguments.join(' ') + ' PASS')
	unsafe { text.free() }
}

fn check() ! {
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	child('repositories', [])!; child('applications', [])!; child('configuration', [])!
	for mode in ['complete', 'check-only', 'preserve', 'export', 'second-index', 'deny-license', 'staged', 'capture-replaced', 'unsafe-retire', 'flush']! {
		before := os.read_file('/proc/kernel-resources')!; println('IMAGE OWNER resources before grace ' + mode + ':\n' + before)
		C.sleep(6)
		after := os.read_file('/proc/kernel-resources')!; println('IMAGE OWNER resources after grace ' + mode + ':\n' + after)
		unsafe { before.free(); after.free() }
		child('owner', ['case', mode, architecture])!
	}
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }; fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-image-owner')
	mut passed := true; check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-image-owner' } else { 'HWTEST FAIL packages-image-owner' })
	C.sync(); C.reboot(0x4321fedc); for { C.sleep(1) }
}
