// SPDX-License-Identifier: GPL-2.0-or-later
module semrangefixture

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/sem.h>
#include <sys/syscall.h>
#include <unistd.h>

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
fn C.strcmp(&char, &char) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C._exit(i32)

fn ctl(id isize, number isize, command isize, argument isize) isize {
	pointer := C.__errno_location()
	unsafe { *pointer = 0 }
	return C.syscall(isize(C.SYS_semctl), id, number, command, argument)
}

fn fatal(stage i32) {
	C.printf(c'LINUX SEMRANGE FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(90)
}

fn check(mut totals Totals, good bool, stage i32) {
	totals.checks++
	if !good {
		totals.failures++
		C.printf(c'LINUX SEMRANGE MISMATCH: stage=%d\n', stage)
	}
}

fn create() isize {
	id := C.syscall(isize(C.SYS_semget), isize(C.IPC_PRIVATE), isize(2), isize(0o600))
	if id < 0 { fatal(1) }
	return id
}

fn remove(id isize) { if ctl(id, 0, C.IPC_RMID, 0) != 0 { fatal(2) } }

fn exercise(mut totals Totals) {
	unsafe {
		id := create()
		stale := create()
		remove(stale)
		parent := C.syscall(isize(C.SYS_getpid))
		mut value := i32(19)
		if ctl(id, 0, C.SETVAL, value) != 0 || ctl(id, 1, C.SETVAL, 23) != 0 { fatal(3) }
		// Raw registers test signed low-word import independently of libc's union.
		ids := [id, isize(u64(id) | u64(0x1234567800000000)), stale, isize(2147483647), isize(-1),
			isize(2147483648), isize(0x12345678ffffffff)]!
		numbers := [isize(0), isize(0x1234567800000000), isize(-1), isize(2), isize(2147483647),
			isize(2147483648)]!
		arguments := [isize(-1), isize(32768), isize(65535), isize(2147483647), isize(2147483648),
			isize(0x12345678ffffffff), isize(0), isize(32767), isize(0x1234567800000001),
			isize(0xffffffff00007fff)]!
		commands := [isize(C.SETVAL), isize(0x1234567800000010)]!
		mut stage := i32(100)
		for command in commands {
			for target in ids {
				for number in numbers {
					for argument in arguments {
						invalid := i32(argument) < 0 || i32(argument) > 32767
						expected := if i32(target) < 0 {
							i32(C.EINVAL)
						} else if invalid {
							i32(C.ERANGE)
						} else if i32(target) != i32(id) || i32(number) != 0 {
							i32(C.EINVAL)
						} else {
							i32(0)
						}
						actual := ctl(target, number, command, argument)
						code := *C.__errno_location()
						check(mut totals, actual == if expected == 0 { isize(0) } else { isize(-1) }
							&& code == expected, stage)
						if expected == 0 { value = i32(argument) }
						// Refused calls must preserve both value and per-index PID.
						check(mut totals, ctl(id, 0, C.GETVAL, 0) == value, stage + 1)
						check(mut totals, ctl(id, 0, C.GETPID, 0) == parent, stage + 2)
						check(mut totals, ctl(id, 1, C.GETVAL, 0) == 23, stage + 3)
						check(mut totals, ctl(id, 1, C.GETPID, 0) == parent, stage + 4)
						stage += 5
					}
				}
			}
		}
		remove(id)
	}
}

@[export: 'main']
fn fixture_main(argc i32, argv &&char) i32 {
	reference := argc == 2 && unsafe { C.strcmp(argv[1], c'--reference') == 0 }
	C.alarm(60)
	mut totals := Totals{}
	exercise(mut totals)
	C.printf(c'LINUX SEMRANGE SUMMARY: checks=%d failures=%d\n', totals.checks, totals.failures)
	if totals.failures != 0 {
		C.puts(c'LINUX SEMRANGE: FAIL')
		C.fflush(unsafe { nil })
		return 1
	}
	C.puts(if reference { c'LINUX SEMRANGE REFERENCE: PASS' } else { c'LINUX SEMRANGE: PASS' })
	C.fflush(unsafe { nil })
	C.alarm(0)
	for { C.pause() }
	return 0
}
