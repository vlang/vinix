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
	println('FFMPEG OWNER PROCESS ' + name + ' ' + arguments.join(' ') + ' PASS')
	unsafe { text.free() }
}

fn check() ! {
	os.setenv('VINIX_PROFILE_EXPORT_SOURCE', '/usr/share/package-fixtures/ffmpeg.tar.xz', true)
	child('metadata', [])!; child('profile', [])!
	for mode in ['complete', 'packed-3', 'packed-6', 'import-elf', 'import-source', 'changed-lock', 'flush', 'cleanup']! {
		before := os.read_file('/proc/kernel-resources')!; println('FFMPEG OWNER resources before grace ' + mode + ':\n' + before)
		C.sleep(6)
		after := os.read_file('/proc/kernel-resources')!; println('FFMPEG OWNER resources after grace ' + mode + ':\n' + after)
		unsafe { before.free(); after.free() }
		child('builder', ['case', mode])!
	}
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }; fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-ffmpeg-owner')
	mut passed := true; check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-ffmpeg-owner' } else { 'HWTEST FAIL packages-ffmpeg-owner' })
	C.sync(); C.reboot(0x4321fedc); for { C.sleep(1) }
}
