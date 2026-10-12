// SPDX-License-Identifier: GPL-2.0-or-later
module capsetfixture

#define __EXPORTED_HEADERS__
#include <errno.h>
#include <grp.h>
#include <linux/capability.h>
#include <stdio.h>
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
fn C._exit(i32)

fn fetch(data &C.__user_cap_data_struct) bool {
	unsafe {
		mut header := C.__user_cap_header_struct{ version: u32(C._LINUX_CAPABILITY_VERSION_3) }
		return C.syscall(isize(C.SYS_capget), &header, data) == 0
	}
}
fn unchanged(wanted [2]C.__user_cap_data_struct) bool {
	unsafe {
		mut actual := [2]C.__user_cap_data_struct{}
		if !fetch(&actual[0]) { return false }
		for index in 0 .. 2 {
			if actual[index].effective != wanted[index].effective || actual[index].permitted != wanted[index].permitted
				|| actual[index].inheritable != wanted[index].inheritable { return false }
		}
		return true
	}
}
fn update(cap u64, scenario i32, wanted [2]C.__user_cap_data_struct, expected_errno i32) bool {
	unsafe {
		mut header := C.__user_cap_header_struct{ version: u32(C._LINUX_CAPABILITY_VERSION_3) }
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		result := C.syscall(isize(C.SYS_capset), &header, &wanted[0])
		expected := if expected_errno == 0 { isize(0) } else { isize(-1) }
		if result != expected || *errno_ptr != expected_errno {
			C.printf(c'LINUX CAPSET MISMATCH: cap=%lu scenario=%d actual=%ld/%d expected=%ld/%d\n', cap,
				scenario, result, *errno_ptr, expected, expected_errno)
			return false
		}
		return true
	}
}
fn ambient(cap u64, expected isize) bool {
	unsafe { return C.syscall(isize(C.SYS_prctl), isize(C.PR_CAP_AMBIENT), u64(1), cap, u64(0), u64(0)) == expected }
}
fn bounded(cap u64, expected isize) bool {
	unsafe { return C.syscall(isize(C.SYS_prctl), isize(C.PR_CAPBSET_READ), cap, u64(0), u64(0), u64(0)) == expected }
}
fn drop(cap u64) bool {
	unsafe { return C.syscall(isize(C.SYS_prctl), isize(C.PR_CAPBSET_DROP), cap, u64(0), u64(0), u64(0)) == 0 }
}
fn root_case(cap u64, scenario i32) bool {
	unsafe {
		mut data := [2]C.__user_cap_data_struct{}
		if !fetch(&data[0]) || !bounded(cap, 1) || !ambient(cap, 0) { return false }
		index := int(cap / 32)
		bit := u32(1) << (cap % 32)
		match scenario {
			0 {
				if !drop(cap) || !bounded(cap, 0) { return false }
				mut requested := data
				requested[index].inheritable |= bit
				if !update(cap, scenario, requested, C.EPERM) || !unchanged(data) || !ambient(cap, 0) { return false }
				data[0].effective &= ~(u32(1) << 8)
				if !update(cap, scenario, data, 0) { return false }
				requested = data
				requested[index].inheritable |= bit
				return update(cap, scenario, requested, C.EPERM) && unchanged(data) && bounded(cap, 0) && ambient(cap, 0)
			}
			1, 2, 5 {
				data[index].permitted &= ~bit
				data[index].effective &= ~bit
				if scenario == 2 { data[0].effective &= ~(u32(1) << 8) }
				if !update(cap, scenario, data, 0) { return false }
				mut requested := data
				requested[index].inheritable |= bit
				if scenario == 5 { requested[0].effective &= ~(u32(1) << 8) }
				if scenario == 2 { return update(cap, scenario, requested, C.EPERM) && unchanged(data) && bounded(cap, 1) && ambient(cap, 0) }
				if !update(cap, scenario, requested, 0) || !unchanged(requested) || !bounded(cap, 1) || !ambient(cap, 0) { return false }
				data = requested
				requested[index].effective |= bit
				return update(cap, scenario, requested, C.EPERM) && unchanged(data) && ambient(cap, 0)
			}
			3 {
				data[index].inheritable |= bit
				if !update(cap, scenario, data, 0)
					|| C.syscall(isize(C.SYS_prctl), isize(C.PR_CAP_AMBIENT), u64(2), cap, u64(0), u64(0)) != 0
					|| !ambient(cap, 1) || !drop(cap) { return false }
				data[index].permitted &= ~bit
				data[index].effective &= ~bit
				if !update(cap, scenario, data, 0) || !ambient(cap, 0) { return false }
				data[0].effective &= ~(u32(1) << 8)
				if !update(cap, scenario, data, 0) || !unchanged(data) { return false }
				mut requested := data
				requested[index].permitted |= bit
				return update(cap, scenario, requested, C.EPERM) && unchanged(data) && bounded(cap, 0) && ambient(cap, 0)
			}
			4 {
				data[0].effective &= ~(u32(1) << 8)
				if !update(cap, scenario, data, 0) { return false }
				data[index].inheritable |= bit
				return update(cap, scenario, data, 0) && unchanged(data) && bounded(cap, 1) && ambient(cap, 0)
			}
			else { return false }
		}
	}
}
fn ordinary_case() bool {
	unsafe {
		if C.setgroups(0, nil) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { return false }
		data := [2]C.__user_cap_data_struct{}
		if !unchanged(data) || !update(0, 6, data, 0) { return false }
		for cap in [u64(0), 40]! {
			mut requested := data
			requested[int(cap / 32)].inheritable |= u32(1) << (cap % 32)
			if !update(cap, 6, requested, C.EPERM) || !unchanged(data) || !bounded(cap, 1) || !ambient(cap, 0) { return false }
		}
		return true
	}
}
fn child(cap u64, scenario i32) bool {
	unsafe {
		C.fflush(nil)
		pid := C.fork()
		if pid < 0 { return false }
		if pid == 0 {
			ok := if scenario == 6 { ordinary_case() } else { root_case(cap, scenario) }
			if ok { C.printf(c'LINUX CAPSET CASE: cap=%lu scenario=%d PASS\n', cap, scenario) }
			C.fflush(nil)
			C._exit(if ok { 0 } else { 1 })
		}
		mut status := i32(-1)
		return C.waitpid(pid, &status, 0) == pid && status == 0
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		mut initial := [2]C.__user_cap_data_struct{}
		if !fetch(&initial[0]) { return 1 }
		mut failed := i32(0)
		for cap in [u64(0), 40]! {
			for scenario in 0 .. 6 {
				if !child(cap, i32(scenario)) { failed++ }
				if !unchanged(initial) || !bounded(cap, 1) || !ambient(cap, 0) { return 1 }
			}
		}
		if !child(0, 6) { failed++ }
		if failed != 0 { C.printf(c'LINUX CAPSET FAIL: conformance mismatches=%d\n', failed) }
		else {
			C.puts(c'LINUX CAPSET PASS: 13 isolated cases, low/high bounding restrictions and effective CAP_SETPCAP authorization')
			C.puts(c'LINUX CAPSET PASS: failed updates preserve sets; inherited exceptions and ambient intersections')
			C.puts(c'LINUX CAPSET: PASS')
		}
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
