// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <unistd.h>
#include <sys/wait.h>
#include <grp.h>
#include <stdlib.h>
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)
fn C.write(int, voidptr, usize) isize
fn C.execv(&char, &&char) int
fn C.setgroups(usize, voidptr) int
fn C.setresgid(u32, u32, u32) int
fn C.setresuid(u32, u32, u32) int
fn C.getresuid(&u32, &u32, &u32) int
fn C.getresgid(&u32, &u32, &u32) int
fn C.getgroups(int, voidptr) int
fn C.unsetenv(&char) int
fn C.getenv(&char) &char
fn C.usleep(u32) int
fn C.kill(int, int) int
fn C.setpgid(int, int) int

fn emit(text string) {
	mut offset := 0
	for offset < text.len {
		written := C.write(1, unsafe { text.str + offset }, usize(text.len - offset))
		if written <= 0 { C._exit(90) }
		offset += int(written)
	}
}

fn ordinary_identity() bool {
	mut real := u32(0)
	mut effective := u32(0)
	mut saved := u32(0)
	if C.getresuid(unsafe { &real }, unsafe { &effective }, unsafe { &saved }) != 0
		|| real != 1000 || effective != 1000 || saved != 1000 { return false }
	if C.getresgid(unsafe { &real }, unsafe { &effective }, unsafe { &saved }) != 0
		|| real != 1000 || effective != 1000 || saved != 1000 { return false }
	return C.getgroups(0, unsafe { nil }) == 0
}

fn main() {
	emit('HWTEST START translator-fork\n')
	pid := C.fork()
	if pid == 0 {
		if C.setpgid(0, 0) != 0 { C._exit(121) }
		if C.setgroups(0, unsafe { nil }) != 0 || C.setresgid(1000, 1000, 1000) != 0
			|| C.setresuid(1000, 1000, 1000) != 0 || !ordinary_identity() { C._exit(124) }
		if C.unsetenv(c'VINIX_ALLOW_WX') != 0 || C.getenv(c'VINIX_ALLOW_WX') != unsafe { nil } { C._exit(123) }
		emit('TRANSLATOR FORK ordinary uid/gid=1000 groups=0 no-WX-exception PASS\n')
		args := ['/qemu-x86_64', '-B', '0x100000000', '-strace', '/fork-probe']!
		mut pointers := unsafe { [6]&char{} }
		for index, argument in args { pointers[index] = &char(argument.str) }
		C.execv(args[0].str, &pointers[0])
		C._exit(122)
	}
	if pid < 0 { emit('HWTEST FAIL translator-fork: native fork\n') }
	else {
		mut status := 0
		mut waited := false
		for _ in 0 .. 6000 {
			if C.waitpid(pid, unsafe { &status }, C.WNOHANG) == pid { waited = true; break }
			C.usleep(10000)
		}
		if !waited {
			C.kill(-pid, 9)
			C.kill(pid, 9)
			C.waitpid(pid, unsafe { &status }, 0)
			emit('HWTEST FAIL translator-fork: timeout\n')
		} else if status == 0 { emit('HWTEST PASS translator-fork\n') }
		else { emit('HWTEST FAIL translator-fork: translated child exit\n') }
		// A failed translated fork may orphan another translator. PID 1 owns
		// this test's descendants; stop the group and reap adopted children.
		if !waited || status != 0 {
			C.kill(-pid, 9)
			for _ in 0 .. 100 {
				if C.waitpid(-1, unsafe { &status }, C.WNOHANG) < 0 { break }
				C.usleep(10000)
			}
		}
	}
	for { C.usleep(1000000) }
}
