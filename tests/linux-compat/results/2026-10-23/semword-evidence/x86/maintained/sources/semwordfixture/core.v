// SPDX-License-Identifier: GPL-2.0-or-later
module semwordfixture

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/sem.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

@[packed]
struct SemOp {
	number u16
	adjustment i16
	flags i16
}

struct C.timespec {
	tv_sec isize
	tv_nsec isize
}

struct Totals {
mut:
	checks i32
	failures i32
}

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.alarm(u32) u32
fn C.strcmp(&char, &char) i32
fn C._exit(i32)

fn clear_errno() {
	pointer := C.__errno_location()
	unsafe { *pointer = 0 }
}

fn get(key u64, count u64, flags u64) isize {
	clear_errno()
	return C.syscall(isize(C.SYS_semget), key, count, flags)
}

fn control(id u64, number u64, command u64, argument u64) isize {
	clear_errno()
	return C.syscall(isize(C.SYS_semctl), id, number, command, argument)
}

fn fatal(stage i32) {
	C.printf(c'LINUX SEMWORD FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(90)
}

fn check(mut totals Totals, actual isize, wanted isize, code i32, stage i32) {
	observed := unsafe { *C.__errno_location() }
	totals.checks++
	if actual != wanted || observed != code {
		totals.failures++
		C.printf(c'LINUX SEMWORD MISMATCH: stage=%d result=%ld/%d expected=%ld/%d\n', stage, actual, observed, wanted, code)
	}
}

fn create(key u64) u64 {
	id := get(key, 2, u64(C.IPC_CREAT | C.IPC_EXCL | 0o600))
	if id < 0 { fatal(1) }
	return u64(id)
}

fn remove(id u64) { if control(id, 0, u64(C.IPC_RMID), 0) != 0 { fatal(2) } }

fn exercise(high u64, mut totals Totals) {
	unsafe {
		// Fresh boot, private IPC namespace: these keys have no outside owner.
		key := u64(0x53495744)
		absent := key + 1
		id := create(key)
		created := get(high, high | 2, high | 0o600)
		check(mut totals, if created >= 0 { 0 } else { created }, 0, 0, 100)
		if created >= 0 { remove(u64(created)) }
		for count in [u64(0), 1, 2]! {
			check(mut totals, get(high | key, high | count, high), isize(id), 0, 101)
		}
		check(mut totals, get(high | key, high | 3, high), -1, C.EINVAL, 102)
		check(mut totals, get(high | absent, high, high), -1, C.ENOENT, 103)
		check(mut totals, get(high | absent, high, high | u64(C.IPC_CREAT)), -1, C.EINVAL, 104)
		check(mut totals, get(high, high, high | 0o600), -1, C.EINVAL, 105)
		// Negative or oversized low words precede key lookup and exclusivity.
		for count in [u64(0xffffffff), 0x80000000, 0xfffffffe, 0x7fffffff]! {
			for flags in [u64(0), u64(C.IPC_CREAT), u64(C.IPC_CREAT | C.IPC_EXCL)]! {
				for queried in [key, absent, u64(0)]! {
					check(mut totals, get(high | queried, high | count, high | flags), -1, C.EINVAL, 106)
				}
			}
		}
		for count in [u64(2), 3]! {
			check(mut totals, get(high | key, high | count, high | u64(C.IPC_CREAT | C.IPC_EXCL)), -1, C.EEXIST, 107)
		}
		if control(id, 1, u64(C.SETVAL), 7) != 0 { fatal(3) }
		check(mut totals, control(high | id, 1, u64(C.GETVAL), 0), 7, 0, 200)
		check(mut totals, control(id, high | 1, u64(C.GETVAL), 0), 7, 0, 201)
		check(mut totals, control(id, 1, high | u64(C.GETVAL), 0), 7, 0, 202)
		check(mut totals, control(high | id, high | 1, high | u64(C.GETVAL), 0), 7, 0, 203)
		check(mut totals, control(high | id, high | 1, high | u64(C.SETVAL), 9), 0, 0, 204)
		check(mut totals, control(id, 1, u64(C.GETVAL), 0), 9, 0, 205)
		check(mut totals, control(id, 0, u64(C.GETVAL), 0), 0, 0, 206)
		for low in [u64(0xffffffff), 0x80000000]! {
			check(mut totals, control(id, high | low, u64(C.GETVAL), 0), -1, C.EINVAL, 207)
			check(mut totals, control(high | low, 1, u64(C.GETVAL), 0), -1, C.EINVAL, 208)
			check(mut totals, control(id, 1, high | low, 0), -1, C.EINVAL, 209)
		}
		mut op := SemOp{ number: 1, adjustment: 1 }
		mut zero := C.timespec{}
		for method in 0 .. 2 {
			clear_errno()
			result := if method == 0 {
				C.syscall(isize(C.SYS_semop), high | id, &op, u64(1))
			} else {
				C.syscall(isize(C.SYS_semtimedop), high | id, &op, u64(1), &zero)
			}
			check(mut totals, result, 0, 0, 300)
			check(mut totals, control(id, 1, u64(C.GETVAL), 0), isize(10 + method), 0, 301)
			for pointer in [voidptr(&op), voidptr(1)]! {
				clear_errno()
				bad := if method == 0 {
					C.syscall(isize(C.SYS_semop), high | 0xffffffff, pointer, u64(1))
				} else {
					C.syscall(isize(C.SYS_semtimedop), high | 0xffffffff, pointer, u64(1), &zero)
				}
				check(mut totals, bad, -1, if pointer == voidptr(1) { i32(C.EFAULT) } else { i32(C.EINVAL) }, 302)
			}
		}
		check(mut totals, control(high | id, high | 0xffffffff, high | u64(C.IPC_RMID), 0), 0, 0, 400)
		// Always clean up if an uncorrected kernel rejected the high-word RMID.
		if totals.failures != 0 && control(id, 0, u64(C.GETVAL), 0) >= 0 { remove(id) }
		check(mut totals, control(id, 1, u64(C.GETVAL), 0), -1, C.EINVAL, 401)
	}
}

@[export: 'main']
pub fn entry(argc i32, argv &&char) i32 {
	reference := argc == 2 && unsafe { C.strcmp(argv[1], c'--reference') == 0 }
	C.alarm(60)
	mut totals := Totals{}
	unsafe {
		for high in [u64(0), u64(1) << 32, u64(0xa5a5a5a500000000), u64(0xffffffff00000000)]! {
			exercise(high, mut totals)
		}
	}
	C.alarm(0)
	C.printf(c'LINUX SEMWORD SUMMARY: checks=%d failures=%d\n', totals.checks, totals.failures)
	C.puts(if totals.failures != 0 { c'LINUX SEMWORD: FAIL' } else if reference {
		c'LINUX SEMWORD REFERENCE: PASS'
	} else { c'LINUX SEMWORD: PASS' })
	C.fflush(unsafe { nil })
	if totals.failures != 0 { return 1 }
	for { C.pause() }
	return 0
}
