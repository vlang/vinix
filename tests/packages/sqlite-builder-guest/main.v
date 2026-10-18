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

fn builder_child(name string, arguments []string) ! {
	mut child := os.new_process('/usr/share/package-fixtures/' + name); child.set_args(arguments); child.set_redirect_stdio_merged()
	child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close(); print(output)
	if code != 0 || output.contains(': fn test_') { return error(name + ' failed (' + code.str() + ')') }
	println('SQLITE BUILDER PROCESS ' + name + ' ' + arguments.join(' ') + ' PASS')
	unsafe { output.free() }
}

fn builder_grace(name string) ! {
	before := os.read_file('/proc/kernel-resources')!; println('SQLITE BUILDER resources before grace ' + name + ':\n' + before)
	C.sleep(6)
	after := os.read_file('/proc/kernel-resources')!; println('SQLITE BUILDER resources after grace ' + name + ':\n' + after)
	unsafe { before.free(); after.free() }
}

fn check() ! {
	for name in ['sqlite-owned', 'sqlite-profile']! { builder_child(name, [])! }
	for mode in ['complete', 'nested', 'version', 'runtime-version', 'runtime-range', 'missing-root', 'missing-architecture', 'wrong-target', 'wrong-mode',
		'missing-notice', 'empty-notice', 'notice-directory', 'no-output-space', 'no-temp-space', 'space-error', 'created',
		'packed-1', 'packed-2', 'packed-3', 'packed-4', 'ready', 'import-elf', 'import-notice',
		'import-directory', 'changed-lock', 'occupied', 'raced-target', 'flush', 'cleanup', 'root-replaced', 'inventory-replaced', 'lock-replaced']! {
		builder_grace(mode)!; builder_child('builder', ['case', mode])!
	}
	for cohort in ['0', '1', '2', '3']! { builder_grace('profile-export-' + cohort)!; builder_child('profile-export', ['sqlite', cohort])! }
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }; fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-sqlite-builder')
	mut passed := true; check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-sqlite-builder' } else { 'HWTEST FAIL packages-sqlite-builder' })
	C.sync(); C.reboot(0x4321fedc); for { C.sleep(1) }
}
