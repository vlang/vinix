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
fn C.sleep(u32) u32

fn creation_grace(name string) ! {
	// Removed filesystem nodes remain charged during the kernel lookup grace.
	// Record that boundary before starting the next independently owned burst.
	before := os.read_file('/proc/kernel-resources')!
	println('WORKSPACE CREATION resources before grace ' + name + ':\n' + before)
	C.sleep(6)
	after := os.read_file('/proc/kernel-resources')!
	println('WORKSPACE CREATION resources after grace ' + name + ':\n' + after)
	unsafe { before.free(); after.free() }
}

fn check() ! {
	os.unsetenv('VINIX_PACKAGE_PACK_CLI')
	for name in ['pack-ownership', 'pack-source', 'copy', 'import-capture', 'import', 'catalog', 'release', 'publisher-io', 'durability', 'distribution', 'coordination', 'service', 'export-stage']! {
		mut child := os.new_process('/usr/share/package-fixtures/' + name)
		child.set_redirect_stdio_merged(); child.run()
		output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
		print(output)
		if code != 0 || output.contains(': fn test_') { return error(name + ' failed (' + code.str() + ')') }
		println('WORKSPACE CREATION PROCESS ' + name + ' PASS')
	}
	// Bound unmeasured no-collector fixture setup/cleanup to one CLI lifetime.
	// Every case retains its original 128 helper or sixteen first-pack calls.
	mut cases := ['paths']
	for deep in [false, true]! {
		for mode in ['export', 'workspace', 'owned']! { cases << 'component-' + mode + '-' + deep.str() }
		for count in [1, 32]! { for mode in ['complete', 'locked', 'hashed', 'copied']! {
			if count == 1 && mode in ['hashed', 'copied']! { continue }
			cases << 'pack-' + count.str() + '-' + deep.str() + '-' + mode
		} }
	}
	for mode in ['existing', 'alias', 'unsafe', 'file-parent', 'create-failure']! { cases << 'refusal-' + mode }
	assert cases.len == 24
	for name in cases {
		creation_grace(name)!
		mut child := os.new_process('/usr/share/package-fixtures/creation')
		child.set_args(['case', name]); child.set_redirect_stdio_merged(); child.run()
		output := child.stdout_slurp(); child.wait(); code := child.code; child.close(); print(output)
		if code != 0 || output.contains(': fn test_') { return error('creation ' + name + ' failed (' + code.str() + ')') }
		println('WORKSPACE CREATION CASE ' + name + ' PASS')
	}
	println('WORKSPACE CREATION PROCESS creation PASS')
	creation_grace('publisher-workspace')!
	for name in ["writers", "admission", "containment", "entries", "retirement"]! {
		mut child := os.new_process("/usr/share/package-fixtures/publisher-workspace")
		child.set_args(["case", name]); child.set_redirect_stdio_merged(); child.run()
		output := child.stdout_slurp(); child.wait(); code := child.code; child.close(); print(output)
		if code != 0 || output.contains(": fn test_") { return error("workspace " + name + " failed (" + code.str() + ")") }
		println("PUBLISHER IO WORKSPACE CASE " + name + " PASS")
	}
	println("WORKSPACE CREATION PROCESS publisher-workspace PASS")
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-workspace-creation-ownership')
	mut passed := true
	check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-workspace-creation-ownership' } else { 'HWTEST FAIL packages-workspace-creation-ownership' })
	C.sync(); C.reboot(0x4321fedc)
	for { C.usleep(1_000_000) }
}
