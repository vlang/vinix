// SPDX-License-Identifier: GPL-2.0-or-later
module seccompqueryfixture

#include <errno.h>
#include <grp.h>
#include <stdio.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

fn C.syscall(isize, ...) isize
fn C.prctl(i32, ...) i32
fn C.__errno_location() &i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn query(action &u32, flags u64, expected i32) bool {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		result := C.syscall(isize(C.SYS_seccomp), isize(2), isize(flags), action)
		want := if expected == 0 { isize(0) } else { isize(-1) }
		if result != want || *errno_ptr != expected {
			C.printf(c'LINUX SECCOMPQUERY FAIL: flags=%lu result=%ld errno=%d expected=%ld/%d\n',
				flags, result, *errno_ptr, want, expected)
			return false
		}
		return true
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		if C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { return 1 }
		for value in [u32(0), 0x80000000, 0x00030000, 0x00050000, 0x7ff00000,
			0x7ffc0000, 0x7fff0000]! {
			mut action := [value, u32(0x13572468)]!
			if !query(&action[0], 0, 0) || !query(&action[0], u64(1) << 32, 0) { return 1 }
			for flags in [u64(1), 2, 4, 8, 16, 32, 0x80000000]! {
				if !query(&action[0], flags, C.EINVAL)
					|| !query(&u32(voidptr(1)), flags, C.EINVAL) { return 1 }
			}
			if action[0] != value || action[1] != 0x13572468 { return 1 }
		}
		mut unknown := u32(0x7fff0001)
		if !query(&unknown, 0, C.EOPNOTSUPP) || unknown != 0x7fff0001
			|| !query(&u32(voidptr(1)), 0, C.EFAULT) { return 1 }
		// Linux's unsigned-int operation also ignores upper register bits.
		mut action := u32(0x7fff0000)
		if C.syscall(isize(C.SYS_seccomp), isize((u64(1) << 32) | 2), isize(0), &action) != 0
			|| C.prctl(C.PR_GET_SECCOMP, isize(0), isize(0), isize(0), isize(0)) != 0 { return 1 }
		C.puts(c'LINUX SECCOMPQUERY: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
