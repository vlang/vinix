// SPDX-License-Identifier: GPL-2.0-or-later
module nnpfixture

#include <errno.h>
#include <grp.h>
#include <stdio.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn check(operation u64, arguments [4]u64, value isize, expected_errno i32) bool {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		result := C.syscall(isize(C.SYS_prctl), operation, arguments[0], arguments[1], arguments[2], arguments[3])
		if result != value || *C.__errno_location() != expected_errno {
			C.printf(c'LINUX NNP FAIL: operation=%lu result=%ld errno=%d expected=%ld/%d\n',
				operation, result, *C.__errno_location(), value, expected_errno)
			return false
		}
		return true
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		if C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { return 1 }
		mut invalid := 0
		for state in 0 .. 2 {
			if !check(u64(C.PR_GET_NO_NEW_PRIVS), [u64(0), 0, 0, 0]!, isize(state), 0) { return 1 }
			for index in 0 .. 4 {
				for bad in [u64(1), u64(1) << 32]! {
					mut arguments := [u64(0), 0, 0, 0]!
					arguments[index] = bad
					if !check(u64(C.PR_GET_NO_NEW_PRIVS), arguments, -1, C.EINVAL) { return 1 }
					invalid++
				}
			}
			if !check((u64(1) << 32) | u64(C.PR_GET_NO_NEW_PRIVS), [u64(0), 0, 0, 0]!, isize(state), 0) { return 1 }
			for bad in [u64(0), 2, (u64(1) << 32) | 1]! {
				if !check(u64(C.PR_SET_NO_NEW_PRIVS), [bad, u64(0), 0, 0]!, -1, C.EINVAL)
					|| !check(u64(C.PR_GET_NO_NEW_PRIVS), [u64(0), 0, 0, 0]!, isize(state), 0) { return 1 }
				invalid++
			}
			for index in 1 .. 4 {
				for bad in [u64(1), u64(1) << 32]! {
					mut arguments := [u64(1), 0, 0, 0]!
					arguments[index] = bad
					if !check(u64(C.PR_SET_NO_NEW_PRIVS), arguments, -1, C.EINVAL)
						|| !check(u64(C.PR_GET_NO_NEW_PRIVS), [u64(0), 0, 0, 0]!, isize(state), 0) { return 1 }
					invalid++
				}
			}
			if !check(u64(C.PR_SET_NO_NEW_PRIVS), [u64(1), 0, 0, 0]!, 0, 0)
				|| !check(u64(C.PR_GET_NO_NEW_PRIVS), [u64(0), 0, 0, 0]!, 1, 0) { return 1 }
		}
		if invalid != 34 { return 1 }
		C.puts(c'LINUX NNP PASS: 34 exact errors, full-width arguments and retained state')
		C.puts(c'LINUX NNP: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
