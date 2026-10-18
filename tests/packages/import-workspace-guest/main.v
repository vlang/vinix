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

fn workspace_child(name string, arguments []string) ! {
	mut child := os.new_process('/usr/share/package-fixtures/' + name)
	child.set_args(arguments); child.set_redirect_stdio_merged(); child.run()
	output := child.stdout_slurp(); child.wait(); code := child.code; child.close(); print(output)
	if code != 0 || output.contains(': fn test_') { return error(name + ' failed (' + code.str() + ')') }
	println('IMPORT WORKSPACE PROCESS ' + name + ' ' + arguments.join(' ') + ' PASS')
}

fn workspace_grace(name string) ! {
	before := os.read_file('/proc/kernel-resources')!
	println('IMPORT WORKSPACE resources before grace ' + name + ':\n' + before)
	C.sleep(6)
	after := os.read_file('/proc/kernel-resources')!
	println('IMPORT WORKSPACE resources after grace ' + name + ':\n' + after)
	unsafe { before.free(); after.free() }
}

fn check() ! {
	os.unsetenv('VINIX_IMPORT_LIMITS_BEFORE')
	for name in ['import-capture', 'import-limits', 'pack-source', 'native-profile']! { workspace_child(name, [])! }
	for name in ['complete', 'pinned', 'opened', 'directory', 'copied', 'publisher-file', 'object-directory', 'manifest-directory']! {
		workspace_grace(name)!; workspace_child('workspace', ['case', name])!
	}
	for name in ['ordinary', 'root-directory', 'root-alias', 'root-mode', 'payload-directory', 'payload-alias', 'manifest-directory', 'manifest-file', 'manifest-alias', 'manifest-fifo', 'manifest-content', 'unexpected-directory', 'renamed-parent', 'creation-refusal', 'public']! {
		workspace_grace(name)!; workspace_child('capture', ['case', name])!
	}
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-import-workspace')
	mut passed := true
	check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-import-workspace' } else { 'HWTEST FAIL packages-import-workspace' })
	C.sync(); C.reboot(0x4321fedc)
	for { C.sleep(1) }
}
