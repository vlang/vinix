// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <grp.h>
$if macos {
	#include <malloc/malloc.h>
} $else {
	#include <malloc.h>
}

fn C.initgroups(&char, u32) i32
fn C.getgroups(i32, &u32) i32
fn C.setgroups(usize, &u32) i32
fn C.setuid(u32) i32
fn C.setgid(u32) i32
fn C.malloc_size(voidptr) usize
fn C.malloc_usable_size(voidptr) usize

fn darwin_process_result(result i32, previous i32) i32 {
	if result < 0 { darwin_set_errno(darwin_native_error(unsafe { *C.ios_errno_address() })) }
	else { darwin_set_errno(previous) }
	return result
}

fn darwin_initgroups(user &char, group i32) i32 {
	if user == unsafe { nil } { darwin_set_errno(14); return -1 }
	previous := unsafe { *C.ios_errno_address() }
	return darwin_process_result(C.initgroups(user, u32(group)), previous)
}

fn darwin_getgroups(count i32, groups &u32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	return darwin_process_result(C.getgroups(count, groups), previous)
}

fn darwin_setgroups(count i32, groups &u32) i32 {
	if count < 0 { darwin_set_errno(22); return -1 }
	previous := unsafe { *C.ios_errno_address() }
	return darwin_process_result(C.setgroups(usize(count), groups), previous)
}

fn darwin_setuid(uid u32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	return darwin_process_result(C.setuid(uid), previous)
}

fn darwin_setgid(gid u32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	return darwin_process_result(C.setgid(gid), previous)
}

fn darwin_kill(pid i32, signal i32) i32 {
	if signal < 0 || signal > 31 { darwin_set_errno(22); return -1 }
	mut native := signal
	$if linux {
		// SIGEMT and SIGINFO have no Linux counterpart. Reject them instead
		// of accidentally delivering Linux SIGBUS or SIGIO to the process.
		if signal in [i32(7), 29] { darwin_set_errno(45); return -1 }
		native = match signal {
			10 { i32(C.SIGBUS) }
			12 { i32(C.SIGSYS) }
			16 { i32(C.SIGURG) }
			17 { i32(C.SIGSTOP) }
			18 { i32(C.SIGTSTP) }
			19 { i32(C.SIGCONT) }
			20 { i32(C.SIGCHLD) }
			23 { i32(C.SIGIO) }
			30 { i32(C.SIGUSR1) }
			31 { i32(C.SIGUSR2) }
			else { signal }
		}
	}
	previous := unsafe { *C.ios_errno_address() }
	return darwin_process_result(C.kill(pid, native), previous)
}

fn darwin_malloc_size(pointer voidptr) usize {
	if pointer == unsafe { nil } { return 0 }
	$if macos { return C.malloc_size(pointer) }
	$else { return C.malloc_usable_size(pointer) }
}

fn process_symbol(symbol string) ?u64 {
	return match symbol {
		'_initgroups' { u64(unsafe { voidptr(darwin_initgroups) }) }
		'_getgroups' { u64(unsafe { voidptr(darwin_getgroups) }) }
		'_setgroups' { u64(unsafe { voidptr(darwin_setgroups) }) }
		'_setuid' { u64(unsafe { voidptr(darwin_setuid) }) }
		'_setgid' { u64(unsafe { voidptr(darwin_setgid) }) }
		'_kill' { u64(unsafe { voidptr(darwin_kill) }) }
		'_malloc_size' { u64(unsafe { voidptr(darwin_malloc_size) }) }
		else { return none }
	}
}
