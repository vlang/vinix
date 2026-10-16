// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <fcntl.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <unistd.h>
fn C.open(&char, int, ...int) int
fn C.close(int) int
fn C.dup2(int, int) int
fn C.fork() int
fn C.setgroups(usize, voidptr) int
fn C.setgid(u32) int
fn C.setuid(u32) int
fn C.execv(&char, &&char) int
fn C._exit(int)
fn C.waitpid(int, &i32, int) int
fn C.reboot(int) int
fn C.usleep(u32) int

fn actor(path string, ordinary bool) bool {
	argv := [c'admin-envelope-fixture', &char(unsafe { nil })]!
	pid := C.fork()
	if pid < 0 { return false }
	if pid == 0 {
		if ordinary {
			if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(90) }
		}
		C.execv(path.str, unsafe { &argv[0] })
		C._exit(91)
	}
	mut status := i32(0)
	return C.waitpid(pid, unsafe { &status }, 0) == pid && status == 0
}

fn check() bool {
	for ordinary in [false, true]! {
		if !actor('/usr/share/package-fixtures/admin-envelope', ordinary) { return false }
		println('ADMIN ENVELOPE ACTOR ' + if ordinary { 'UID 1000 PASS' } else { 'root PASS' })
	}
	for name in ['protocol', 'authcore', 'socket']! {
		if !actor('/usr/share/package-fixtures/' + name, false) { return false }
		println('ADMIN ENVELOPE COMPANION ' + name + ' PASS')
	}
	return true
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-admin-envelope')
	passed := check()
	println(if passed { 'HWTEST PASS packages-admin-envelope' } else { 'HWTEST FAIL packages-admin-envelope' })
	C.reboot(0x4321fedc)
	for { C.usleep(1_000_000) }
}
