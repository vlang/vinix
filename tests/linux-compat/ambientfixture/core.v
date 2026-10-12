// SPDX-License-Identifier: GPL-2.0-or-later
module ambientfixture

#define __EXPORTED_HEADERS__
#include <errno.h>
#include <grp.h>
#include <linux/capability.h>
#include <stdio.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

struct C.__user_cap_header_struct { mut: version u32 pid i32 }
struct C.__user_cap_data_struct { mut: effective u32 permitted u32 inheritable u32 }

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn call(command u64, arguments [3]u64, result isize, expected_errno i32) bool {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		actual := C.syscall(isize(C.SYS_prctl), isize(C.PR_CAP_AMBIENT), command, arguments[0], arguments[1], arguments[2])
		if actual != result || *errno_ptr != expected_errno {
			C.printf(c'LINUX AMBIENT FAIL: command=%lu arguments=%lu/%lu/%lu actual=%ld/%d expected=%ld/%d\n', command,
				arguments[0], arguments[1], arguments[2], actual, *errno_ptr, result, expected_errno)
			return false
		}
		return true
	}
}
fn unchanged(wanted isize) bool { return call(1, [u64(0), 0, 0]!, wanted, 0) }
fn invalid(wanted isize) bool {
	unsafe {
		for command in [u64(1), 2, 3, 4]! {
			for index in 0 .. 3 {
				if index == 0 && command != 4 { continue }
				for value in [u64(1), u64(1) << 32, u64(-1)]! {
					mut arguments := [u64(0), 0, 0]!
					arguments[index] = value
					if !call(command, arguments, -1, C.EINVAL) || !unchanged(wanted) { return false }
				}
			}
		}
		return true
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		mut header := C.__user_cap_header_struct{ version: u32(C._LINUX_CAPABILITY_VERSION_3) }
		mut data := [2]C.__user_cap_data_struct{}
		if C.syscall(isize(C.SYS_capget), &header, &data[0]) != 0 { return 1 }
		data[0].inheritable |= 1
		if C.syscall(isize(C.SYS_capset), &header, &data[0]) != 0 || !unchanged(0) { return 1 }
		// A malformed clear must leave an actually raised ambient capability.
		if !call(2, [u64(0), 0, 0]!, 0, 0) || !unchanged(1) || !invalid(1) { return 1 }
		if !call(3, [u64(0), 0, 0]!, 0, 0) || !unchanged(0) || !invalid(0)
			|| !call(2, [u64(0), 0, 0]!, 0, 0) || !call(4, [u64(0), 0, 0]!, 0, 0) || !unchanged(0) { return 1 }
		if C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0
			|| !invalid(0) || !call(2, [u64(0), 0, 0]!, -1, C.EPERM)
			|| !call(3, [u64(0), 0, 0]!, 0, 0) || !call(4, [u64(0), 0, 0]!, 0, 0) || !unchanged(0) { return 1 }
		C.puts(c'LINUX AMBIENT PASS: 81 exact errors, full-width reserved arguments and unchanged state')
		C.puts(c'LINUX AMBIENT: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
