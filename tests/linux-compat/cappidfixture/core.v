// SPDX-License-Identifier: GPL-2.0-or-later
module cappidfixture

#define __EXPORTED_HEADERS__
#include <errno.h>
#include <grp.h>
#include <linux/capability.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}
struct C.__user_cap_header_struct { mut: version u32 pid i32 }
struct C.__user_cap_data_struct { mut: effective u32 permitted u32 inheritable u32 }
struct Peer { mut: stage i32 tid i32 parent i32 failed bool }
fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
fn C.sched_yield() i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

const version3 = u32(0x20080522)
fn unchanged(wanted [2]C.__user_cap_data_struct) bool {
	unsafe {
		mut header := C.__user_cap_header_struct{ version: version3 }
		mut actual := [2]C.__user_cap_data_struct{}
		if C.syscall(isize(C.SYS_capget), &header, &actual[0]) != 0 { return false }
		for index in 0 .. 2 {
			if actual[index].effective != wanted[index].effective || actual[index].permitted != wanted[index].permitted
				|| actual[index].inheritable != wanted[index].inheritable { return false }
		}
		return true
	}
}
fn call(version u32, pid i32, data voidptr, expected_errno i32) bool {
	unsafe {
		mut header := C.__user_cap_header_struct{ version: version pid: pid }
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		result := C.syscall(isize(C.SYS_capset), &header, data)
		expected := if expected_errno == 0 { isize(0) } else { isize(-1) }
		if result != expected || *errno_ptr != expected_errno {
			C.printf(c'LINUX CAPPID FAIL: version=%u pid=%d data=%lu actual=%ld/%d expected=%ld/%d\n',
				version, pid, usize(data), result, *errno_ptr, expected, expected_errno)
			return false
		}
		return true
	}
}
fn basic(data [2]C.__user_cap_data_struct) bool {
	unsafe {
		own := i32(C.syscall(isize(C.SYS_gettid)))
		for version in [u32(0x19980330), u32(0x20071026), version3]! {
			for pid in [i32(-1), i32(-2147483648), i32(2147483647), i32(1000000)]! {
				for pointer in [voidptr(&data[0]), voidptr(nil), voidptr(1)]! {
					if !call(version, pid, pointer, C.EPERM) || !unchanged(data) { return false }
				}
			}
			for pid in [i32(0), own]! {
				for pointer in [voidptr(nil), voidptr(1)]! {
					if !call(version, pid, pointer, C.EFAULT) || !unchanged(data) { return false }
				}
			}
		}
		for pointer in [voidptr(nil), voidptr(1)]! {
			errno_ptr := C.__errno_location()
			*errno_ptr = 0
			if C.syscall(isize(C.SYS_capset), pointer, &data[0]) != -1 || *errno_ptr != C.EFAULT || !unchanged(data) { return false }
		}
		return call(version3, 0, voidptr(&data[0]), 0) && unchanged(data)
			&& call(version3, own, voidptr(&data[0]), 0) && unchanged(data)
	}
}
fn other(pid i32, data [2]C.__user_cap_data_struct) bool {
	unsafe {
		for version in [u32(0x19980330), u32(0x20071026), version3]! {
			for pointer in [voidptr(&data[0]), voidptr(nil), voidptr(1)]! {
				if !call(version, pid, pointer, C.EPERM) || !unchanged(data) { return false }
			}
		}
		return true
	}
}
fn worker(argument voidptr) voidptr {
	unsafe {
		mut peer := &Peer(argument)
		peer.tid = i32(C.syscall(isize(C.SYS_gettid)))
		mut header := C.__user_cap_header_struct{ version: version3 }
		mut data := [2]C.__user_cap_data_struct{}
		peer.failed = peer.tid == peer.parent || C.syscall(isize(C.SYS_capget), &header, &data[0]) != 0
		C.__atomic_store_n(&peer.stage, 1, 3)
		for C.__atomic_load_n(&peer.stage, 2) != 2 { C.sched_yield() }
		if !peer.failed { peer.failed = !basic(data) || !other(peer.parent, data) }
		return nil
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		for level in 0 .. 2 {
			if level == 1 && (C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0) { return 1 }
			mut header := C.__user_cap_header_struct{ version: version3 }
			mut data := [2]C.__user_cap_data_struct{}
			if C.syscall(isize(C.SYS_capget), &header, &data[0]) != 0 || !basic(data) { return 1 }
			mut peer := Peer{ parent: i32(C.syscall(isize(C.SYS_gettid))) }
			mut handle := C.pthread_t{}
			if C.pthread_create(&handle, nil, worker, &peer) != 0 { return 1 }
			for C.__atomic_load_n(&peer.stage, 2) != 1 { C.sched_yield() }
			ok := other(peer.tid, data)
			C.__atomic_store_n(&peer.stage, 2, 3)
			if C.pthread_join(handle, nil) != 0 || !ok || peer.failed || !unchanged(data) { return 1 }
			C.printf(c'LINUX CAPPID PASS: level=%ld leader and sibling self IDs, exact refusals and unchanged sets\n', isize(level))
		}
		C.puts(c'LINUX CAPPID PASS: 236 exact errors, three versions, PID permission before data faults')
		C.puts(c'LINUX CAPPID: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
