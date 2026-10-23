// SPDX-License-Identifier: GPL-2.0-or-later
module semabifixture

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/sem.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

@[packed]
struct SemOp {
	number     u16
	adjustment i16
	flags      i16
}

struct C.timespec {
	tv_sec  isize
	tv_nsec isize
}

struct Totals {
mut:
	checks   i32
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
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32
fn C.sysconf(i32) isize
fn C._exit(i32)

fn ctl(id i32, command i32, argument u64) isize {
	return C.syscall(isize(C.SYS_semctl), isize(id), isize(0), isize(command), argument)
}

fn fatal(stage i32) {
	C.printf(c'LINUX SEMABI FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(90)
}

fn check(mut totals Totals, good bool, stage i32) {
	totals.checks++
	if !good {
		totals.failures++
		C.printf(c'LINUX SEMABI MISMATCH: stage=%d\n', stage)
	}
}

fn create() i32 {
	id := i32(C.syscall(isize(C.SYS_semget), isize(C.IPC_PRIVATE), isize(1), isize(0o600)))
	if id < 0 { fatal(1) }
	return id
}

fn remove(id i32) { if ctl(id, C.IPC_RMID, 0) != 0 { fatal(2) } }

fn operation(method i32, id i32, operations voidptr, count u64, timeout voidptr, wanted i32, stage i32, mut totals Totals) {
	e := C.__errno_location()
	unsafe { *e = 0 }
	actual := if method == 0 {
		C.syscall(isize(C.SYS_semop), isize(id), operations, count)
	} else {
		C.syscall(isize(C.SYS_semtimedop), isize(id), operations, count, timeout)
	}
	code := unsafe { *e }
	check(mut totals, actual == if wanted == 0 { isize(0) } else { isize(-1) } && code == wanted, stage)
	if code != wanted || actual != if wanted == 0 { isize(0) } else { isize(-1) } {
		C.printf(c'LINUX SEMABI DETAIL: stage=%d method=%d id=%d count=%016lx result=%ld/%d expected=%d\n', stage, method, id, count, actual, code, wanted)
	}
}

fn vectors(mut totals Totals) {
	unsafe {
		id := create()
		stale := create()
		remove(stale)
		mut ops := [32]SemOp{}
		mut zero := C.timespec{}
		for method in 0 .. 2 {
			for high in [u64(0), u64(1) << 32, u64(0xa5a5a5a500000000), u64(0xffffffff00000000)]! {
				operation(method, id, &ops[0], high | 1, &zero, 0, 100, mut totals)
				operation(method, id, &ops[0], high | 32, &zero, 0, 101, mut totals)
				operation(method, id, nil, high, &zero, C.EINVAL, 102, mut totals)
				operation(method, id, nil, high | 1, &zero, C.EFAULT, 103, mut totals)
				operation(method, id, voidptr(1), high | 1, &zero, C.EFAULT, 104, mut totals)
				operation(method, id, nil, high | 0xffffffff, &zero, C.E2BIG, 105, mut totals)
				operation(method, -1, &ops[0], high | 1, &zero, C.EINVAL, 106, mut totals)
				operation(method, -1, nil, high | 1, &zero, C.EFAULT, 107, mut totals)
				operation(method, -1, nil, high | 0xffffffff, &zero, C.E2BIG, 108, mut totals)
				operation(method, stale, &ops[0], high | 1, &zero, C.EINVAL, 109, mut totals)
				operation(method, stale, voidptr(1), high | 1, &zero, C.EFAULT, 110, mut totals)
			}
			for flags in [i16(1), i16(0x100), i16(0x2000), i16(-1)]! {
				ops[0] = SemOp{ flags: flags }
				operation(method, id, &ops[0], 1, &zero, 0, 111, mut totals)
			}
			ops[0] = SemOp{ number: 1 }
			operation(method, id, &ops[0], 1, &zero, C.EFBIG, 112, mut totals)
			ops[0] = SemOp{}
		}
		check(mut totals, ctl(id, C.GETVAL, 0) == 0, 113)
		// A vector straddling a guard page must fault before changing any value.
		page := C.sysconf(C._SC_PAGESIZE)
		if page <= 0 { fatal(3) }
		region := C.mmap(nil, usize(page * 2), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if region == voidptr(-1) { fatal(4) }
		if C.mprotect(voidptr(usize(region) + usize(page)), usize(page), C.PROT_NONE) != 0 {
			fatal(5)
		}
		last := &SemOp(usize(region) + usize(page) - sizeof(SemOp))
		*last = SemOp{ adjustment: 1 }
		for method in 0 .. 2 {
			operation(method, id, last, 2, &zero, C.EFAULT, 114, mut totals)
			check(mut totals, ctl(id, C.GETVAL, 0) == 0, 115)
		}
		if C.munmap(region, usize(page * 2)) != 0 { fatal(6) }
		remove(id)
	}
}

fn timeouts(mut totals Totals) {
	unsafe {
		id := create()
		mut op := SemOp{}
		for count in [u64(0), 1, 0xffffffff]! {
			for number in [id, i32(-1)]! {
				operation(1, number, &op, count, voidptr(1), C.EFAULT, 200, mut totals)
			}
		}
		for bad in [C.timespec{ tv_sec: -1 }, C.timespec{ tv_nsec: -1 },
			C.timespec{ tv_nsec: 1000000000 }]! {
			mut duration := bad
			operation(1, id, &op, 1, &duration, C.EINVAL, 201, mut totals)
			operation(1, id, voidptr(1), 1, &duration, C.EFAULT, 202, mut totals)
			operation(1, id, &op, 0xffffffff, &duration, C.E2BIG, 203, mut totals)
		}
		operation(1, id, &op, 1, nil, 0, 204, mut totals)
		remove(id)
	}
}

fn values(mut totals Totals) {
	unsafe {
		id := create()
		for high in [u64(0), u64(1) << 32, u64(0xa5a5a5a500000000), u64(0xffffffff00000000)]! {
			for low in [u32(0), 1, 32767, 32768, 0x7fffffff, 0x80000000, 0xffffffff]! {
				before := ctl(id, C.GETVAL, 0)
				e := C.__errno_location()
				*e = 0
				actual := ctl(id, C.SETVAL, high | u64(low))
				code := *e
				wanted := if low <= 32767 { i32(0) } else { i32(C.ERANGE) }
				check(mut totals, actual == if wanted == 0 { isize(0) } else { isize(-1) } && code == wanted, 300)
				if code != wanted {
					C.printf(c'LINUX SEMABI SETVAL: word=%016lx result=%ld/%d expected=%d\n', high | u64(low), actual, code, wanted)
				}
				check(mut totals, ctl(id, C.GETVAL, 0) == if wanted == 0 {
					isize(low)
				} else {
					before
				}, 301)
			}
		}
		remove(id)
	}
}

@[export: 'main']
pub fn entry(argc i32, argv &&char) i32 {
	reference := argc == 2 && unsafe { C.strcmp(argv[1], c'--reference') == 0 }
	C.alarm(60)
	mut totals := Totals{}
	vectors(mut totals)
	timeouts(mut totals)
	values(mut totals)
	C.alarm(0)
	C.printf(c'LINUX SEMABI SUMMARY: checks=%d failures=%d\n', totals.checks, totals.failures)
	C.puts(if totals.failures != 0 {
		c'LINUX SEMABI: FAIL'
	} else if reference {
		c'LINUX SEMABI REFERENCE: PASS'
	} else {
		c'LINUX SEMABI: PASS'
	})
	C.fflush(unsafe { nil })
	if totals.failures != 0 { return 1 }
	for { C.pause() }
	return 0
}
