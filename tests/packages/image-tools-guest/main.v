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

fn child(path string, args []string, expected int, marker string) ! {
	mut process := os.new_process(path); process.set_args(args); process.set_redirect_stdio_merged()
	process.run(); text := process.stdout_slurp(); process.wait(); code := process.code; process.close(); print(text)
	if code != expected || !text.contains(marker) { return error('staged tool failed: ' + path) }
}

fn check() ! {
	child('/usr/share/package-fixtures/image-tools', [], 0, 'IMAGE TOOLS 58')!
	child('/usr/bin/vinix-package', ['--help'], 0, 'usage: vinix-package')!
	child('/usr/bin/vinix-package', ['--json', 'status'], 0, '"architecture":')!
	child('/usr/sbin/vinix-session', [], 2, 'usage: vinix-session')!
	child('/usr/libexec/vinix/vinix-linux-runner', [], 126, 'usage: vinix-linux-runner')!
	println('IMAGE TOOLS native production-staged package/session/Linux-runner execution PASS')
	before := os.read_file('/proc/kernel-resources')!; println('IMAGE TOOLS resources before grace:\n' + before)
	C.sleep(6)
	after := os.read_file('/proc/kernel-resources')!; println('IMAGE TOOLS resources after grace:\n' + after)
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }; fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-image-tools')
	mut passed := true; check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-image-tools' } else { 'HWTEST FAIL packages-image-tools' })
	C.sync(); C.reboot(0x4321fedc); for { C.sleep(1) }
}
