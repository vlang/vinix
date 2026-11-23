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
fn C.execl(&char, &char, ...voidptr) int
fn C._exit(int)
fn C.waitpid(int, &i32, int) int
fn C.reboot(int) int
fn C.usleep(u32) int

fn check(executable &char, name &char) bool {
	pid := C.fork()
	if pid < 0 { return false }
	if pid == 0 {
		C.execl(executable, name, voidptr(0))
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
	streams := check(c'/usr/share/package-fixtures/streams', c'streams')
	if streams { println('LAUNCH SOCKET EOF and descriptor regressions PASS') }
	admin := check(c'/usr/share/package-fixtures/admin-socket', c'admin-socket')
	if admin { println('ADMIN SOCKET interrupted waits PASS') }
	println(if streams && admin { 'HWTEST PASS packages-launch-socket' } else { 'HWTEST FAIL packages-launch-socket' })
	C.reboot(0x4321fedc)
	for { C.usleep(1_000_000) }
}
