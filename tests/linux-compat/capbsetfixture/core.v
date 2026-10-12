// SPDX-License-Identifier: GPL-2.0-or-later
module capbsetfixture

#define __EXPORTED_HEADERS__
#include <errno.h>
#include <grp.h>
#include <linux/capability.h>
#include <stdio.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
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
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.execl(&char, &char, ...) i32
fn C._exit(i32)
fn C.strcmp(&char, &char) i32

const all_caps = (u64(1) << 41) - 1
fn call(option isize, cap u64, result isize, expected_errno i32) bool {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		actual := C.syscall(isize(C.SYS_prctl), option, cap, u64(0), u64(0), u64(0))
		if actual != result || *errno_ptr != expected_errno {
			C.printf(c'LINUX CAPBSET FAIL: option=%ld cap=%lu actual=%ld/%d expected=%ld/%d\n',
				option, cap, actual, *errno_ptr, result, expected_errno)
			return false
		}
		return true
	}
}
fn bounding(expected u64) bool {
	for cap in 0 .. 41 {
		if !call(isize(C.PR_CAPBSET_READ), u64(cap), isize((expected >> cap) & 1), 0) { return false }
	}
	return true
}
fn errors(permission bool, expected u64) bool {
	unsafe {
		for cap in [u64(41), u64(0xffffffff), u64(1) << 32, (u64(1) << 32) | 8, u64(1) << 63, u64(-1)]! {
			if !call(isize(C.PR_CAPBSET_DROP), cap, -1, if permission { C.EINVAL } else { C.EPERM })
				|| !call(isize(C.PR_CAPBSET_READ), cap, -1, C.EINVAL) || !bounding(expected) { return false }
		}
		if !permission {
			for cap in [u64(0), 8, 40]! {
				if !call(isize(C.PR_CAPBSET_DROP), cap, -1, C.EPERM) || !bounding(expected) { return false }
			}
		}
		return true
	}
}
fn capabilities(header &C.__user_cap_header_struct, original [2]C.__user_cap_data_struct) bool {
	unsafe {
		mut data := [2]C.__user_cap_data_struct{}
		if C.syscall(isize(C.SYS_capget), header, &data[0]) != 0 { return false }
		for index in 0 .. 2 {
			if data[index].effective != original[index].effective || data[index].permitted != original[index].permitted
				|| data[index].inheritable != original[index].inheritable { return false }
		}
		return true
	}
}
fn child(exec_probe bool, expected u64) bool {
	unsafe {
		C.fflush(nil)
		pid := C.fork()
		if pid < 0 { return false }
		if pid == 0 {
			if !bounding(expected) { C._exit(1) }
			if exec_probe {
				C.execl(c'/sbin/init', c'init', c'capbset-exec', voidptr(nil))
				C._exit(2)
			}
			if !call(isize(C.PR_CAPBSET_DROP), 40, 0, 0) || !bounding(expected & ~(u64(1) << 40)) { C._exit(3) }
			C.puts(c'LINUX CAPBSET CHILD: fork inherited bounding set; child drop stayed private')
			C.fflush(nil)
			C._exit(0)
		}
		mut status := i32(-1)
		return C.waitpid(pid, &status, 0) == pid && status == 0 && bounding(expected)
	}
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		if argc == 2 && C.strcmp(argv[1], c'capbset-exec') == 0 {
			if !bounding(all_caps & ~u64(1) & ~(u64(1) << 40)) { return 1 }
			C.puts(c'LINUX CAPBSET CHILD: exec retained low/high bounding drops')
			C.fflush(nil)
			return 0
		}
		mut header := C.__user_cap_header_struct{ version: u32(C._LINUX_CAPABILITY_VERSION_3) }
		mut data := [2]C.__user_cap_data_struct{}
		if C.syscall(isize(C.SYS_capget), &header, &data[0]) != 0 || !bounding(all_caps) || !errors(true, all_caps) { return 1 }
		original := data
		// UID 0 alone cannot authorize a drop, even with CAP_SETPCAP permitted.
		data[0].effective &= ~(u32(1) << 8)
		if C.syscall(isize(C.SYS_capset), &header, &data[0]) != 0 || !errors(false, all_caps) { return 1 }
		data[0].effective = original[0].effective
		if C.syscall(isize(C.SYS_capset), &header, &data[0]) != 0
			|| !call(isize(C.PR_CAPBSET_DROP), 0, 0, 0) || !call(isize(C.PR_CAPBSET_DROP), 0, 0, 0)
			|| !bounding(all_caps & ~u64(1)) || !capabilities(&header, original) || !child(false, all_caps & ~u64(1))
			|| !call(isize(C.PR_CAPBSET_DROP), 40, 0, 0) || !call(isize(C.PR_CAPBSET_DROP), 40, 0, 0) { return 1 }
		expected := all_caps & ~u64(1) & ~(u64(1) << 40)
		if !bounding(expected) || !capabilities(&header, original) || !child(true, expected)
			|| C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 || !errors(false, expected) { return 1 }
		C.puts(c'LINUX CAPBSET PASS: 42 exact errors, effective permission precedence, unchanged sets and full-width arguments')
		C.puts(c'LINUX CAPBSET PASS: low/high idempotent drops, fork isolation and exec inheritance')
		C.puts(c'LINUX CAPBSET: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
