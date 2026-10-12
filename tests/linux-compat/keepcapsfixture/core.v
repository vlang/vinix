// SPDX-License-Identifier: GPL-2.0-or-later
module keepcapsfixture

#include <errno.h>
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.fork() i32
fn C.execl(&char, &char, ...) i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.strcmp(&char, &char) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn state() isize {
	return unsafe { C.syscall(isize(C.SYS_prctl), u64(C.PR_GET_KEEPCAPS), u64(0), u64(0), u64(0), u64(0)) }
}
fn set(value u64, expected isize, expected_errno i32) bool {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		actual := C.syscall(isize(C.SYS_prctl), u64(C.PR_SET_KEEPCAPS), value, u64(0), u64(0), u64(0))
		if actual != expected || *errno_ptr != expected_errno {
			C.printf(c'LINUX KEEPCAPS FAIL: value=%lu result=%ld errno=%d expected=%ld/%d\n', value, actual, *errno_ptr, expected, expected_errno)
			return false
		}
		return true
	}
}
fn fork_exec(wanted isize) bool {
	unsafe {
		pid := C.fork()
		if pid < 0 { return false }
		if pid == 0 {
			if state() != wanted { C._exit(11) }
			C.execl(c'/proc/self/exe', c'init', c'--after-exec', voidptr(nil))
			C._exit(12)
		}
		mut result := i32(0)
		return C.waitpid(pid, &result, 0) == pid && result == 0 && state() == wanted
	}
}
fn validate() bool {
	unsafe {
		for wanted in 0 .. 2 {
			if !set(u64(wanted), 0, 0) || state() != isize(wanted) { return false }
			for value in [u64(2), u64(-1), u64(1) << 32, (u64(1) << 32) | 1,
				u64(1) << 63, (u64(1) << 63) | 1]! {
				if !set(value, -1, C.EINVAL) || state() != isize(wanted) { return false }
			}
			if !set(u64(wanted), 0, 0) || !fork_exec(isize(wanted)) { return false }
		}
		return set(0, 0, 0) && state() == 0
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		if argc == 2 {
			if C.strcmp(argv[1], c'--after-exec') != 0 || state() != 0 { return 13 }
			C.puts(c'LINUX KEEPCAPS CHILD: exec cleared flag')
			return 0
		}
		if !validate() { return 1 }
		if C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 || !validate() { return 1 }
		C.puts(c'LINUX KEEPCAPS PASS: 24 exact errors, root/user state, fork inheritance and exec reset')
		C.puts(c'LINUX KEEPCAPS: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
