// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <fcntl.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <unistd.h>
fn C.dup2(int, int) int
fn C.fork() int
fn C.setgroups(usize, voidptr) int
fn C.setgid(u32) int
fn C.setuid(u32) int
fn C.execv(&char, &&char) int
fn C._exit(int)
fn C.waitpid(int, &i32, int) int
fn C.sync()
fn C.reboot(int) int
fn C.usleep(u32) int

fn actor(ordinary bool) ! {
	argv := [c'launch-transport', &char(unsafe { nil })]!
	pid := C.fork()
	if pid < 0 { return error('cannot start launch-transport worker') }
	if pid == 0 {
		if ordinary {
			if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(90) }
		}
		C.execv(c'/usr/share/package-fixtures/launch-transport', unsafe { &argv[0] })
		C._exit(91)
	}
	mut status := i32(0)
	if C.waitpid(pid, unsafe { &status }, 0) != pid || status != 0 { return error('launch-transport worker failed') }
	println('LAUNCH TRANSPORT ACTOR ' + if ordinary { 'UID 1000 PASS' } else { 'root PASS' })
}

fn check() ! {
	actor(false)!
	actor(true)!
	for name in ['protocol', 'streams', 'command']! {
		mut child := os.new_process('/usr/share/package-fixtures/' + name)
		child.set_redirect_stdio_merged(); child.run()
		output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
		print(output)
		if code != 0 || output.contains(': fn test_') || output.contains('V panic:') { return error('${name} failed (${code})') }
		println('LAUNCH TRANSPORT COMPANION ' + name + ' PASS')
	}
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-launch-transport')
	mut passed := true
	check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-launch-transport' } else { 'HWTEST FAIL packages-launch-transport' })
	C.sync(); C.reboot(0x4321fedc)
	for { C.usleep(1_000_000) }
}
