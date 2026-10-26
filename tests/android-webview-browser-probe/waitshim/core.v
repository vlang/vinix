// SPDX-License-Identifier: GPL-2.0-or-later
// Diagnostic only. Observe the existing wait, never consume another status.
@[has_globals]
module waitshim

#include <sys/wait.h>
#include <unistd.h>
#include <dlfcn.h>
#include <errno.h>
#include <sched.h>
#define vinix_wait_idtype idtype_t

@[typedef]
struct C.vinix_wait_idtype {}

@[typedef]
struct C.siginfo_t {
mut:
	si_pid i32
	si_code i32
	si_status i32
}

type NativeWait = fn (C.vinix_wait_idtype, u32, &C.siginfo_t, i32) i32

struct Line {
mut:
	bytes [256]u8
	used int
}

__global (
	wp_native_wait uint
	wp_resolve_lock u8
	wp_reports u32
)

@[c_extern]
__global C.errno i32

fn C.dlsym(voidptr, &char) voidptr
fn C.memcpy(voidptr, voidptr, uint) voidptr
fn C.write(i32, voidptr, uint) int
fn C.sched_yield() i32
fn C.__atomic_load_n(&uint, i32) uint
fn C.__atomic_store_n(&uint, uint, i32)
fn C.__atomic_test_and_set(&u8, i32) bool
fn C.__atomic_clear(&u8, i32)

fn (mut line Line) literal(value &char) {
	unsafe {
		mut i := 0
		for value[i] != 0 && line.used < line.bytes.len {
			line.bytes[line.used] = u8(value[i]); line.used++; i++
		}
	}
}

fn (mut line Line) number(value i64) {
	unsafe {
		mut magnitude := u64(if value < 0 { -value } else { value })
		if value < 0 { line.literal(c'-') }
		mut digits := [20]u8{}
		mut count := 0
		for {
			digits[count] = `0` + u8(magnitude % 10)
			count++
			magnitude /= 10
			if magnitude == 0 { break }
		}
		for count > 0 && line.used < line.bytes.len {
			count--; line.bytes[line.used] = digits[count]; line.used++
		}
	}
}

fn report(kind i32, id u32, options i32, info &C.siginfo_t) {
	unsafe {
		// Saturate the counter: even billions of polls cannot wrap it and
		// enable more output. The lock is not held during the native wait.
		for C.__atomic_test_and_set(&wp_resolve_lock, 2) { C.sched_yield() }
		allowed := wp_reports < 32
		if allowed { wp_reports++ }
		C.__atomic_clear(&wp_resolve_lock, 3)
		if !allowed { return }
		mut line := Line{}
		line.literal(c'BROWSER-WAITID idtype='); line.number(kind)
		line.literal(c' id='); line.number(id)
		line.literal(c' options='); line.number(options)
		line.literal(c' pid='); line.number(info.si_pid)
		line.literal(c' code='); line.number(info.si_code)
		line.literal(c' status='); line.number(info.si_status)
		line.literal(c'\n')
		// One bounded write; a failed/partial diagnostic never retries waitid.
		C.write(2, &line.bytes[0], uint(line.used))
	}
}

pub fn interposed(kind i32, id u32, info &C.siginfo_t, options i32) i32 {
	unsafe {
		incoming_errno := C.errno
		mut address := C.__atomic_load_n(&wp_native_wait, 2)
		if address == 0 {
			for C.__atomic_test_and_set(&wp_resolve_lock, 2) { C.sched_yield() }
			address = C.__atomic_load_n(&wp_native_wait, 2)
			if address == 0 {
				address = uint(C.dlsym(voidptr(uint(-1)), c'waitid'))
				C.__atomic_store_n(&wp_native_wait, address, 3)
			}
			C.__atomic_clear(&wp_resolve_lock, 3)
		}
		if address == 0 { C.errno = C.ENOSYS; return -1 }
		// dlsym and lock contention must not alter the errno seen by libc.
		mut native_kind := C.vinix_wait_idtype{}
		C.memcpy(&native_kind, &kind, sizeof(i32))
		C.errno = incoming_errno
		result := NativeWait(address)(native_kind, id, info, options)
		saved_errno := C.errno
		if result == 0 && info != nil && info.si_pid > 0 { report(kind, id, options, info) }
		C.errno = saved_errno
		return result
	}
}

$if wait_probe_preload ? {
	// Use libc's enum in the public declaration; its int representation on
	// the pinned AArch64 musl ABI is copied without changing the value.
	@[export: 'waitid']
	pub fn native_interposed(kind C.vinix_wait_idtype, id u32, info &C.siginfo_t, options i32) i32 {
		unsafe {
			mut numeric := i32(0)
			C.memcpy(&numeric, &kind, sizeof(i32))
			return interposed(numeric, id, info, options)
		}
	}
}
