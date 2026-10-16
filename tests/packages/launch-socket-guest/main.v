// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <fcntl.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <unistd.h>
fn C.dup2(int, int) int
fn C.open(&char, int, ...int) int
fn C.close(int) int
fn C.fork() int
fn C.execv(&char, &&char) int
fn C._exit(int)
fn C.waitpid(int, &i32, int) int
fn C.reboot(int) int
fn C.usleep(u32) int

fn check() bool {
	argv := [c'streams', &char(unsafe { nil })]!
	pid := C.fork()
	if pid < 0 { return false }
	if pid == 0 {
		C.execv(c'/usr/share/package-fixtures/streams', unsafe { &argv[0] })
		C._exit(91)
	}
	mut status := i32(0)
	return C.waitpid(pid, unsafe { &status }, 0) == pid && status == 0
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-launch-socket')
	passed := check()
	if passed { println('LAUNCH SOCKET EOF and descriptor regressions PASS') }
	println(if passed { 'HWTEST PASS packages-launch-socket' } else { 'HWTEST FAIL packages-launch-socket' })
	C.reboot(0x4321fedc)
	for { C.usleep(1_000_000) }
}
