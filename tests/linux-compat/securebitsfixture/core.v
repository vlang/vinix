// SPDX-License-Identifier: GPL-2.0-or-later
module securebitsfixture

#define __EXPORTED_HEADERS__
#include <errno.h>
#include <grp.h>
#include <linux/capability.h>
#include <linux/securebits.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}
struct C.__user_cap_header_struct { mut: version u32 pid i32 }
struct C.__user_cap_data_struct { mut: effective u32 permitted u32 inheritable u32 }
struct Peer { mut: stage i32 failed i32 }
struct Descendant { mut: wanted isize failed i32 }
struct DirectExec { mut: stage i32 wanted u32 }

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.setuid(u32) i32
fn C.getuid() u32
fn C.fork() i32
fn C.execl(&char, &char, ...) i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
fn C.sched_yield() i32
fn C.strcmp(&char, &char) i32
fn C.strtoul(&char, voidptr, i32) usize
fn C.strtoull(&char, voidptr, i32) u64
fn C.snprintf(&char, usize, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

const cap_all = (u64(1) << 41) - 1

fn prctl(option i32, value u64, result isize, expected_errno i32) bool {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		actual := C.syscall(isize(C.SYS_prctl), isize(option), value, u64(0), u64(0), u64(0))
		if actual != result || *errno_ptr != expected_errno {
			C.printf(c'LINUX SECUREBITS FAIL: option=%d value=%lu actual=%ld/%d expected=%ld/%d\n', option, value, actual, *errno_ptr, result, expected_errno)
			return false
		}
		return true
	}
}
fn flags(wanted isize) bool { return prctl(C.PR_GET_SECUREBITS, 0, wanted, 0) }
fn caps() [3]u64 {
	unsafe {
		mut header := C.__user_cap_header_struct{ version: u32(C._LINUX_CAPABILITY_VERSION_3) }
		mut data := [2]C.__user_cap_data_struct{}
		if C.syscall(isize(C.SYS_capget), &header, &data[0]) != 0 { return [u64(-1), -1, -1]! }
		return [u64(data[0].effective) | (u64(data[1].effective) << 32),
			u64(data[0].permitted) | (u64(data[1].permitted) << 32),
			u64(data[0].inheritable) | (u64(data[1].inheritable) << 32)]!
	}
}
fn capset(effective u64, permitted u64, inheritable u64) bool {
	unsafe {
		mut header := C.__user_cap_header_struct{ version: u32(C._LINUX_CAPABILITY_VERSION_3) }
		data := [C.__user_cap_data_struct{u32(effective), u32(permitted), u32(inheritable)},
			C.__user_cap_data_struct{u32(effective >> 32), u32(permitted >> 32), u32(inheritable >> 32)}]!
		return C.syscall(isize(C.SYS_capset), &header, &data[0]) == 0
	}
}
fn ambient(command u64, capability u64, result isize, expected_errno i32) bool {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		actual := C.syscall(isize(C.SYS_prctl), isize(C.PR_CAP_AMBIENT), command, capability, u64(0), u64(0))
		return actual == result && *errno_ptr == expected_errno
	}
}
fn exec_probe(wanted u32, permitted u64) i32 {
	unsafe {
		mut bits := [32]char{}
		mut limit := [32]char{}
		C.snprintf(&bits[0], usize(bits.len), c'%u', wanted & ~u32(C.SECBIT_KEEP_CAPS))
		C.snprintf(&limit[0], usize(limit.len), c'%lx', permitted)
		C.execl(c'/proc/self/exe', c'init', c'--after-exec', &bits[0], &limit[0], voidptr(nil))
		return 11
	}
}
fn lock_pair(index i32, enabled bool) i32 {
	unsafe {
		bit := u32(1) << (u32(index) * 2)
		lock_mask := bit << 1
		wanted := lock_mask | if enabled { bit } else { u32(0) }
		if !prctl(C.PR_SET_SECUREBITS, u64(wanted), 0, 0) || !flags(isize(wanted))
			|| !prctl(C.PR_SET_SECUREBITS, u64(wanted ^ bit), -1, C.EPERM)
			|| !prctl(C.PR_SET_SECUREBITS, u64(wanted & ~lock_mask), -1, C.EPERM)
			|| !flags(isize(wanted)) || !prctl(C.PR_SET_SECUREBITS, u64(wanted), 0, 0) { return 12 }
		if index == 2 {
			if !prctl(C.PR_SET_KEEPCAPS, 0, -1, C.EPERM)
				|| !prctl(C.PR_SET_KEEPCAPS, 1, -1, C.EPERM)
				|| !prctl(C.PR_SET_KEEPCAPS, 2, -1, C.EINVAL) || !flags(isize(wanted)) { return 13 }
		}
		// A different, unlocked behavior bit remains mutable.
		other := if index == 3 { u32(C.SECBIT_KEEP_CAPS) } else { u32(C.SECBIT_NO_CAP_AMBIENT_RAISE) }
		changed := wanted | other
		if !prctl(C.PR_SET_SECUREBITS, u64(changed), 0, 0) || !flags(isize(changed)) { return 14 }
		return exec_probe(changed, if changed & u32(C.SECBIT_NOROOT) != 0 { u64(0) } else { cap_all })
	}
}
fn policy_case(index i32) i32 {
	unsafe {
		if index == 0 {
			if C.setuid(1000) != 0 || !prctl(C.PR_SET_SECUREBITS, 0, -1, C.EPERM)
				|| !prctl(C.PR_SET_SECUREBITS, 16, -1, C.EPERM) || !flags(0)
				|| !prctl(C.PR_SET_KEEPCAPS, 1, 0, 0) || !flags(16)
				|| !prctl(C.PR_SET_SECUREBITS, 16, -1, C.EPERM) || !flags(16)
				|| !prctl(C.PR_SET_KEEPCAPS, 0, 0, 0) || !flags(0) { return 15 }
			return 0
		}
		if index == 1 {
			// Dropping CAP_SETPCAP also denies the call while uid remains zero.
			remaining := cap_all & ~(u64(1) << u32(C.CAP_SETPCAP))
			if !capset(remaining, remaining, 0) || !prctl(C.PR_SET_SECUREBITS, 0, -1, C.EPERM) || !flags(0) { return 16 }
			return 0
		}
		if !capset(cap_all, cap_all, 1) || !ambient(2, 0, 0, 0) || !ambient(1, 0, 1, 0) { return 17 }
		if index == 2 {
			if !prctl(C.PR_SET_SECUREBITS, u64(C.SECBIT_NO_CAP_AMBIENT_RAISE | C.SECBIT_NO_CAP_AMBIENT_RAISE_LOCKED), 0, 0)
				|| !ambient(1, 0, 1, 0) || !ambient(3, 0, 0, 0) || !ambient(2, 0, -1, C.EPERM)
				|| !ambient(1, 0, 0, 0) || !ambient(4, 0, 0, 0) { return 18 }
			return 0
		}
		if index == 3 {
			if !prctl(C.PR_SET_SECUREBITS, u64(C.SECBIT_NO_SETUID_FIXUP), 0, 0)
				|| C.setuid(1000) != 0 || caps() != [cap_all, cap_all, u64(1)]!
				|| !ambient(1, 0, 1, 0) || C.setuid(0) != 0 || C.getuid() != 0 { return 19 }
			return 0
		}
		// KEEP_CAPS alone retains permitted, clears effective and ambient.
		if !prctl(C.PR_SET_KEEPCAPS, 1, 0, 0) || C.setuid(1000) != 0
			|| caps() != [u64(0), cap_all, u64(1)]! || !ambient(1, 0, 0, 0) { return 20 }
		return 0
	}
}
fn inherited(argument voidptr) voidptr {
	unsafe {
		mut child := &Descendant(argument)
		if !flags(child.wanted) || !prctl(C.PR_GET_KEEPCAPS, 0, 1, 0) { child.failed = 1 }
		return nil
	}
}
fn peer(argument voidptr) voidptr {
	unsafe {
		mut context := &Peer(argument)
		if !flags(0) { context.failed = 1 }
		C.__atomic_store_n(&context.stage, 1, 3)
		for C.__atomic_load_n(&context.stage, 2) != 2 { C.sched_yield() }
		if !flags(0) || !prctl(C.PR_SET_KEEPCAPS, 1, 0, 0) || !flags(16) { context.failed = 1 }
		mut child := Descendant{ wanted: 16 }
		mut handle := C.pthread_t{}
		if C.pthread_create(&handle, nil, inherited, &child) != 0 || C.pthread_join(handle, nil) != 0 || child.failed != 0 { context.failed = 1 }
		pid := C.fork()
		if pid == 0 {
			if !flags(16) { C._exit(21) }
			C._exit(exec_probe(16, cap_all))
		}
		mut result := i32(0)
		if pid < 0 || C.waitpid(pid, &result, 0) != pid || result != 0 || !flags(16) { context.failed = 1 }
		C.__atomic_store_n(&context.stage, 3, 3)
		for C.__atomic_load_n(&context.stage, 2) != 4 { C.sched_yield() }
		return nil
	}
}
fn exec_peer(argument voidptr) voidptr {
	unsafe {
		mut request := &DirectExec(argument)
		if !flags(0) { C._exit(24) }
		C.__atomic_store_n(&request.stage, 1, 3)
		for C.__atomic_load_n(&request.stage, 2) != 2 { C.sched_yield() }
		if !prctl(C.PR_SET_SECUREBITS, u64(request.wanted), 0, 0) { C._exit(25) }
		C._exit(exec_probe(request.wanted, cap_all))
		return nil
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		if argc == 3 && C.strcmp(argv[1], c'--peer-exec') == 0 {
			mut request := DirectExec{ wanted: u32(C.strtoul(argv[2], nil, 10)) }
			mut handle := C.pthread_t{}
			if !flags(0) || C.pthread_create(&handle, nil, exec_peer, &request) != 0 { return 26 }
			for C.__atomic_load_n(&request.stage, 2) != 1 { C.sched_yield() }
			if !prctl(C.PR_SET_SECUREBITS, if request.wanted == 16 { u64(64) } else { u64(16) }, 0, 0) { return 27 }
			C.__atomic_store_n(&request.stage, 2, 3)
			for { C.pause() }
		}
		if argc == 4 {
			wanted := isize(C.strtoul(argv[2], nil, 10))
			limit := C.strtoull(argv[3], nil, 16)
			if C.strcmp(argv[1], c'--after-exec') != 0 || !flags(wanted)
				|| !prctl(C.PR_GET_KEEPCAPS, 0, 0, 0) || caps()[0] != limit || caps()[1] != limit { return 22 }
			if wanted & isize(C.SECBIT_KEEP_CAPS_LOCKED) != 0
				&& (!prctl(C.PR_SET_KEEPCAPS, 0, -1, C.EPERM) || !prctl(C.PR_SET_KEEPCAPS, 1, -1, C.EPERM)) { return 23 }
			C.puts(c'LINUX SECUREBITS CHILD: exec flags and locks')
			return 0
		}
		if !flags(0) { return 1 }
		for bad in [u64(256), u64(1) << 32, (u64(1) << 32) | 1, u64(-1)]! {
			if !prctl(C.PR_SET_SECUREBITS, bad, -1, C.EPERM) || !flags(0) { return 1 }
		}
		for wanted in [&char(c'16'), &char(c'64')]! {
			pid := C.fork()
			if pid < 0 { return 1 }
			if pid == 0 {
				C.execl(c'/proc/self/exe', c'init', c'--peer-exec', wanted, voidptr(nil))
				C._exit(28)
			}
			mut result := i32(0)
			if C.waitpid(pid, &result, 0) != pid || result != 0 || !flags(0) { C.puts(c'LINUX SECUREBITS FAIL: direct nonleader exec'); return 1 }
		}
		for index in 0 .. 13 {
			pid := C.fork()
			if pid < 0 { return 1 }
			if pid == 0 { C._exit(if index < 8 { lock_pair(i32(index / 2), index % 2 != 0) } else { policy_case(i32(index - 8)) }) }
			mut result := i32(0)
			if C.waitpid(pid, &result, 0) != pid || result != 0 || !flags(0) {
				C.printf(c'LINUX SECUREBITS FAIL: child=%d outcome=%d\n', index, result)
				return 1
			}
		}
		C.puts(c'LINUX SECUREBITS PASS: four lock pairs, exact refusals, UID and ambient policy, exec preservation')
		mut context := Peer{}
		mut handle := C.pthread_t{}
		if C.pthread_create(&handle, nil, peer, &context) != 0 { return 1 }
		for C.__atomic_load_n(&context.stage, 2) != 1 { C.sched_yield() }
		if !prctl(C.PR_SET_SECUREBITS, 64, 0, 0) { return 1 }
		C.__atomic_store_n(&context.stage, 2, 3)
		for C.__atomic_load_n(&context.stage, 2) != 3 { C.sched_yield() }
		valid := context.failed == 0 && flags(64) && prctl(C.PR_GET_KEEPCAPS, 0, 0, 0)
		C.__atomic_store_n(&context.stage, 4, 3)
		if C.pthread_join(handle, nil) != 0 || !valid || !prctl(C.PR_SET_SECUREBITS, 0, 0, 0) { C.puts(c'LINUX SECUREBITS FAIL: task ownership/inheritance'); return 1 }
		C.puts(c'LINUX SECUREBITS PASS: sibling independence and clone/fork/exec inheritance')
		C.puts(c'LINUX SECUREBITS: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
