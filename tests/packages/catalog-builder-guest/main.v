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
	println('CATALOG BUILDER PROCESS ' + name + ' ' + arguments.join(' ') + ' PASS')
	unsafe { text.free() }
}

fn check() ! {
	child('plan', [])!; child('flush', [])!; child('catalog', [])!
	for mode in ['complete', 'unresolved', 'alias-source', 'packed-3', 'packed-5', 'import-missing', 'manifest-mutated', 'object-mutated', 'flush', 'root-replaced-refused']! {
		before := os.read_file('/proc/kernel-resources')!; println('CATALOG BUILDER resources before grace ' + mode + ':\n' + before)
		C.sleep(6)
		after := os.read_file('/proc/kernel-resources')!; println('CATALOG BUILDER resources after grace ' + mode + ':\n' + after)
		unsafe { before.free(); after.free() }
		child('builder', ['case', mode])!
	}
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }; fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-catalog-builder')
	mut passed := true; check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-catalog-builder' } else { 'HWTEST FAIL packages-catalog-builder' })
	C.sync(); C.reboot(0x4321fedc); for { C.sleep(1) }
}
