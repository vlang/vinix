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
		for count in [1, 64, 4096]! { run_fixture('catalog-decode', ['--catalog-decode-case', 'owned-' + architecture + '-' + count.str()])! }
	}
	for selection in ['legacy', 'refusals', 'bounds', 'nested', 'pack']! { run_fixture('catalog-decode', ['--catalog-decode-case', selection])! }
	println('CATALOG PROCESS catalog-decode PASS')
	for name in ['publisher-schema', 'catalog', 'composition']! {
		run_fixture(name, [])!
		println('CATALOG PROCESS ' + name + ' PASS')
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
	println('HWTEST START packages-catalog-decode')
	mut passed := true
	check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-catalog-decode' } else { 'HWTEST FAIL packages-catalog-decode' })
	C.sync(); C.reboot(0x4321fedc)
	for { C.usleep(1_000_000) }
}
