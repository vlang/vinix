// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strings

#include <fcntl.h>
#include <sys/reboot.h>
#include <unistd.h>
fn C.dup2(int, int) int
fn C.sync()
fn C.reboot(int) int
fn C.usleep(u32) int

fn run_worker(name string) ! {
	println('IMAGE REQUIREMENTS PROCESS ${name} START')
	mut child := os.new_process('/usr/share/package-fixtures/' + name)
	child.set_redirect_stdio_merged()
	child.run()
	defer { child.close() }
	mut output := strings.new_builder(4096)
	for {
		chunk, count := os.fd_read(child.stdio_fd[int(os.ChildProcessPipeKind.stdout)], 4096)
		if count < 0 {
			child.signal_kill()
			child.wait()
			return error('could not read ${name} output')
		}
		if count == 0 { break }
		print(chunk)
		output.write_string(chunk)
	}
	child.wait()
	if child.code != 0 || output.str().contains(': fn test_') {
		return error('${name} failed (${child.code})')
	}
	println('IMAGE REQUIREMENTS PROCESS ${name} PASS')
}

fn check() ! {
	os.setenv('VINIX_PACKAGE_STAGE_CHECK_CLI', '/usr/share/package-fixtures/stage-check', true)
	for name in ['image-requirements', 'image-check', 'image-repositories', 'image-configuration', 'release', 'catalog', 'deployment', 'resolve']! {
		run_worker(name)!
	}
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-image-requirements')
	mut passed := true
	check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-image-requirements' } else { 'HWTEST FAIL packages-image-requirements' })
	C.sync(); C.reboot(0x4321fedc)
	for { C.usleep(1_000_000) }
}
