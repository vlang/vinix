// SPDX-License-Identifier: GPL-2.0-or-later
// Capture completion does not qualify translated execution. The unchanged
// wine-fork-probe judges the arithmetic and fork workload independently.
module main

#include <unistd.h>
#include <sys/wait.h>
#include <grp.h>
#include <stdlib.h>
#include <errno.h>
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
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
fn C.kill(i32, i32) i32
fn C.setpgid(i32, i32) i32

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
	emit('HWTEST START translator-fork-jit-capture\n')
	pid := C.fork()
	if pid == 0 {
		if C.setpgid(0, 0) != 0 { C._exit(121) }
		if C.setgroups(0, unsafe { nil }) != 0 || C.setresgid(1000, 1000, 1000) != 0
			|| C.setresuid(1000, 1000, 1000) != 0 || !ordinary_identity() { C._exit(124) }
		if C.unsetenv(c'VINIX_ALLOW_WX') != 0 || C.getenv(c'VINIX_ALLOW_WX') != unsafe { nil } { C._exit(123) }
		emit('TRANSLATOR JIT ordinary uid/gid=1000 groups=0 no-WX-exception PASS\n')
		// With no -D, QEMU logs to inherited stderr; opening /dev/console
		// again is correctly refused for this ordinary identity.
		args := ['/qemu-x86_64', '-B', '0x100000000', '-d', 'out_asm', '/fork-probe']!
		mut pointers := unsafe { [7]&char{} }
		for index, argument in args { pointers[index] = &char(argument.str) }
		C.execv(args[0].str, &pointers[0])
		C._exit(122)
	}
	if pid < 0 { emit('HWTEST FAIL translator-fork-jit-capture: native fork\n') }
	else {
		mut status := i32(0)
		mut waited := false
		mut wait_error := false
		for _ in 0 .. 6000 {
			result := C.waitpid(pid, unsafe { &status }, C.WNOHANG)
			if result == pid { waited = true; break }
			if result < 0 && C.errno != C.EINTR { wait_error = true; break }
			C.usleep(10000)
		}
		if !waited {
			C.kill(-pid, 9)
			C.kill(pid, 9)
			for _ in 0 .. 100 {
				if C.waitpid(pid, unsafe { &status }, 0) >= 0 || C.errno != C.EINTR { break }
			}
			if wait_error { emit('HWTEST FAIL translator-fork-jit-capture: wait\n') }
			else { emit('HWTEST FAIL translator-fork-jit-capture: timeout\n') }
		} else {
			if status == 0 { emit('TRANSLATOR JIT translated command exit zero\n') }
			else { emit('TRANSLATOR JIT translated command exit nonzero\n') }
			emit('HWTEST PASS translator-fork-jit-capture\n')
		}
		if !waited || status != 0 {
			C.kill(-pid, 9)
			for _ in 0 .. 100 {
				result := C.waitpid(-1, unsafe { &status }, C.WNOHANG)
				if result < 0 && C.errno != C.EINTR { break }
				C.usleep(10000)
			}
		}
	}
	for { C.usleep(1000000) }
}
