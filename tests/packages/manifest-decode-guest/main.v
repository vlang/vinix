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
	for architecture in ['aarch64', 'x86_64']! {
		for mode in ['template', 'inventory']! {
			for count in [1, 64, 16384]! { run_fixture('manifest-decode', ['--manifest-case', 'owned-' + architecture + '-' + mode + '-' + count.str()])! }
		}
	}
	for selection in ['defaults', 'refusals', 'bounds', 'pack']! { run_fixture('manifest-decode', ['--manifest-case', selection])! }
	println('MANIFEST PROCESS manifest-decode PASS')
	for name in ['index-schema', 'configuration-observation']! {
		run_fixture(name, [])!
		println('MANIFEST PROCESS ' + name + ' PASS')
	}
}

fn run_fixture(name string, args []string) ! {
	mut child := os.new_process('/usr/share/package-fixtures/' + name)
	child.set_args(args)
	child.set_redirect_stdio_merged(); child.run()
	output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	print(output)
	if code != 0 || output.contains(': fn test_') { return error('${name} failed (${code})') }
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-manifest-decode')
	mut passed := true
	check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-manifest-decode' } else { 'HWTEST FAIL packages-manifest-decode' })
	C.sync(); C.reboot(0x4321fedc)
	for { C.usleep(1_000_000) }
}
