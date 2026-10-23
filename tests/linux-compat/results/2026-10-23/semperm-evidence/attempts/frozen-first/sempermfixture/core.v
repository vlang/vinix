// SPDX-License-Identifier: GPL-2.0-or-later
module sempermfixture

#include <errno.h>
#include <linux/capability.h>
#include <stdio.h>
#include <string.h>
#include <sys/sem.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.__user_cap_header_struct {
mut:
	version u32
	pid     i32
}

struct C.__user_cap_data_struct {
mut:
	effective   u32
	permitted   u32
	inheritable u32
}

struct C.sembuf {
mut:
	sem_num u16
	sem_op  i16
	sem_flg i16
}

struct Totals {
mut:
	checks   i32
	failures i32
}

struct Stamp {
	sec  i64
	nsec i64
}

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.strcmp(&char, &char) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C.fork() i32
fn C.pipe(&i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)

fn fatal(stage i32) {
	C.printf(c'LINUX SEMPERM FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(90)
}

fn check(mut t Totals, good bool, stage int) {
	t.checks++
	if !good {
		t.failures++
		// Bound serial output even on the deliberately broken baseline kernel.
		if t.failures <= 12 { C.printf(c'LINUX SEMPERM MISMATCH: stage=%d\n', stage) }
	}
}

fn ctl(id isize, number isize, command isize, argument isize) isize {
	unsafe { *C.__errno_location() = 0 }
	return C.syscall(isize(C.SYS_semctl), id, number, command, argument)
}

fn result(mut t Totals, actual isize, code i32, expected isize, stage int) {
	check(mut t, actual == if code == 0 { expected } else { isize(-1) }
		&& unsafe { *C.__errno_location() } == code, stage)
}

fn credentials(scenario int) {
	unsafe {
		mut header := C.__user_cap_header_struct{ version: u32(C._LINUX_CAPABILITY_VERSION_3) }
		mut data := [2]C.__user_cap_data_struct{}
		if C.syscall(isize(C.SYS_capget), &header, &data[0]) != 0 { fatal(10) }
		mut groups := [u32(9999), u32(2001)]!
		if C.syscall(isize(C.SYS_setgroups), isize(if scenario == 2 { 2 } else { 1 }), &groups[0]) != 0 {
			fatal(11)
		}
		gid := if scenario == 1 { isize(2001) } else { isize(9999) }
		if C.syscall(isize(C.SYS_setresgid), isize(0), gid, isize(0)) != 0 { fatal(12) }
		uid := if scenario == 0 {
			isize(1001)
		} else if scenario == 4 {
			isize(0)
		} else {
			isize(1002)
		}
		if C.syscall(isize(C.SYS_setresuid), isize(if scenario == 5 { 1001 } else { 0 }), uid, isize(0)) != 0 {
			fatal(13)
		}
		if scenario == 6 {
			data[0].effective = u32(1) << 6 | u32(1) << 7
			data[1].effective = 0
			if C.syscall(isize(C.SYS_capset), &header, &data[0]) != 0 { fatal(14) }
			C.syscall(isize(C.SYS_setfsuid), isize(1001))
			C.syscall(isize(C.SYS_setfsgid), isize(2001))
			if C.syscall(isize(C.SYS_setfsuid), isize(-1)) != 1001 || C.syscall(isize(C.SYS_setfsgid), isize(-1)) != 2001 {
				fatal(15)
			}
		}
		caps := if scenario == 7 {
			u32(1) << 15
		} else if scenario == 8 {
			u32(1) << 21
		} else if scenario == 9 {
			u32(1) << 15 | u32(1) << 21
		} else {
			u32(0)
		}
		data[0].effective = caps
		data[1].effective = 0
		if C.syscall(isize(C.SYS_capset), &header, &data[0]) != 0
			|| C.syscall(isize(C.SYS_capget), &header, &data[0]) != 0
			|| data[0].effective != caps || data[1].effective != 0
			|| C.syscall(isize(C.SYS_geteuid)) != uid || C.syscall(isize(C.SYS_getegid)) != gid {
			fatal(16)
		}
	}
}

fn exercise(mut t Totals, ids &isize, removal &isize, scenario int) {
	unsafe {
		credentials(scenario)
		override := scenario == 7 || scenario == 9
		for mode in 0 .. 512 {
			id := ids[mode]
			key := isize(0x534d0000 + mode)
			granted := if scenario == 0 {
				mode >> 6
			} else if scenario in [1, 2] {
				mode >> 3
			} else {
				mode
			}
			read := granted & 4 != 0 || override
			alter := granted & 2 != 0 || override
			rcode := if read { i32(0) } else { i32(C.EACCES) }
			wcode := if alter { i32(0) } else { i32(C.EACCES) }
			stage := scenario * 100000 + mode * 100
			for request in 0 .. 8 {
				// All permission columns are folded, including execute bits.
				for shift in [0, 3, 6]! {
					*C.__errno_location() = 0
					actual := C.syscall(isize(C.SYS_semget), key, isize(0), isize(request << shift))
					code := if request & ~granted & 7 == 0 || override {
						i32(0)
					} else {
						i32(C.EACCES)
					}
					result(mut t, actual, code, id, stage + request * 3 + shift / 3)
				}
			}
			for command in [C.GETVAL, C.GETPID, C.GETNCNT, C.GETZCNT]! {
				actual := ctl(id, 0, command, 0)
				// GETPID changes after successful zero/net-zero operations in earlier children.
				check(mut t, if read {
					actual >= 0 && *C.__errno_location() == 0
				} else {
					actual == -1 && *C.__errno_location() == C.EACCES
				}, stage + 24)
				result(mut t, ctl(id, -1, command, 0), if read { i32(C.EINVAL) } else { rcode }, 0, stage + 25)
			}
			mut values := [u16(0x5555), u16(0x6666)]!
			result(mut t, ctl(id, -1, C.GETALL, isize(&values[0])), rcode, 0, stage + 32)
			check(mut t, values == if read {
				[u16(0), u16(0)]!
			} else {
				[u16(0x5555), u16(0x6666)]!
			}, stage + 33)
			result(mut t, ctl(id, 0, C.GETALL, 0), if read { i32(C.EFAULT) } else { rcode }, 0, stage + 34)
			result(mut t, ctl(id, 0, C.SETVAL, 0), wcode, 0, stage + 35)
			result(mut t, ctl(id, -1, C.SETVAL, 0), C.EINVAL, 0, stage + 36)
			result(mut t, ctl(id, -1, C.SETVAL, 32768), C.ERANGE, 0, stage + 37)
			values = [u16(0), u16(0)]!
			result(mut t, ctl(id, -1, C.SETALL, isize(&values[0])), wcode, 0, stage + 38)
			result(mut t, ctl(id, 0, C.SETALL, 0), if alter { i32(C.EFAULT) } else { wcode }, 0, stage + 39)
			values[1] = 32768
			result(mut t, ctl(id, 0, C.SETALL, isize(&values[0])), if alter {
				i32(C.ERANGE)
			} else {
				wcode
			}, 0, stage + 40)
			result(mut t, ctl(id, -1, 0x123456, 0), C.EINVAL, 0, stage + 41)
			mut zero := C.sembuf{ sem_num: 0, sem_op: 0, sem_flg: i16(C.IPC_NOWAIT) }
			mut pair := [C.sembuf{ sem_num: 0, sem_op: 1, sem_flg: i16(C.IPC_NOWAIT) },
				C.sembuf{ sem_num: 0, sem_op: -1, sem_flg: i16(C.IPC_NOWAIT) }]!
			mut invalid := [C.sembuf{ sem_num: 0, sem_op: -1 }, C.sembuf{ sem_num: 2, sem_op: 0 }]!
			stamp := Stamp{}
			for timed in [false, true]! {
				*C.__errno_location() = 0
				actual := C.syscall(isize(C.SYS_semtimedop), id, &zero, isize(1), if timed {
					voidptr(&stamp)
				} else {
					nil
				})
				result(mut t, actual, rcode, 0, stage + 42)
				*C.__errno_location() = 0
				changed := C.syscall(isize(C.SYS_semtimedop), id, &pair[0], isize(2), if timed {
					voidptr(&stamp)
				} else {
					nil
				})
				result(mut t, changed, wcode, 0, stage + 43)
				*C.__errno_location() = 0
				bad := C.syscall(isize(C.SYS_semtimedop), id, &invalid[0], isize(2), if timed {
					voidptr(&stamp)
				} else {
					nil
				})
				result(mut t, bad, C.EFBIG, 0, stage + 44)
			}
			*C.__errno_location() = 0
			result(mut t, C.syscall(isize(C.SYS_semget), key, isize(3), isize(0o777)), C.EINVAL, 0, stage + 48)
			*C.__errno_location() = 0
			result(mut t, C.syscall(isize(C.SYS_semget), key, isize(0), isize(C.IPC_CREAT | C.IPC_EXCL | 0o777)), C.EEXIST, 0, stage + 49)
		}
		for index in 0 .. 4 {
			result(mut t, ctl(removal[index], -1, C.IPC_RMID, 0), if scenario in [0, 8, 9] {
				i32(0)
			} else {
				i32(C.EPERM)
			}, 0, 1000000 + scenario * 10 + index)
		}
	}
}

fn create(key isize, mode isize) isize {
	id := C.syscall(isize(C.SYS_semget), key, isize(2), mode | isize(C.IPC_CREAT | C.IPC_EXCL))
	if id < 0 { fatal(1) }
	return id
}

fn main_cases(mut t Totals) {
	unsafe {
		mut ids := [512]isize{}
		if C.syscall(isize(C.SYS_setresgid), isize(-1), isize(2001), isize(-1)) != 0
			|| C.syscall(isize(C.SYS_setresuid), isize(-1), isize(1001), isize(-1)) != 0 {
			fatal(2)
		}
		for mode in 0 .. 512 { ids[mode] = create(isize(0x534d0000 + mode), isize(mode)) }
		if C.syscall(isize(C.SYS_setresuid), isize(-1), isize(0), isize(-1)) != 0
			|| C.syscall(isize(C.SYS_setresgid), isize(-1), isize(0), isize(-1)) != 0 {
			fatal(3)
		}
		for scenario in 0 .. 10 {
			mut removal := [4]isize{}
			if C.syscall(isize(C.SYS_setresgid), isize(-1), isize(2001), isize(-1)) != 0
				|| C.syscall(isize(C.SYS_setresuid), isize(-1), isize(1001), isize(-1)) != 0 {
				fatal(4)
			}
			for index in 0 .. 4 { removal[index] = create(C.IPC_PRIVATE, isize(index * 0o222)) }
			if C.syscall(isize(C.SYS_setresuid), isize(-1), isize(0), isize(-1)) != 0
				|| C.syscall(isize(C.SYS_setresgid), isize(-1), isize(0), isize(-1)) != 0 {
				fatal(5)
			}
			mut pipe := [2]i32{}
			if C.pipe(&pipe[0]) != 0 { fatal(6) }
			child := C.fork()
			if child < 0 { fatal(7) }
			if child == 0 {
				C.close(pipe[0])
				mut local := Totals{}
				exercise(mut local, &ids[0], &removal[0], scenario)
				C.fflush(nil)
				if C.write(pipe[1], &local, sizeof(Totals)) != sizeof(Totals) { C._exit(91) }
				C._exit(0)
			}
			C.close(pipe[1])
			mut local := Totals{}
			if C.read(pipe[0], &local, sizeof(Totals)) != sizeof(Totals) { fatal(8) }
			C.close(pipe[0])
			mut status := i32(-1)
			if C.waitpid(child, &status, 0) != child || status != 0 { fatal(9) }
			t.checks += local.checks
			t.failures += local.failures
			for index in 0 .. 4 {
				// The old kernel also incorrectly lets unauthorized children remove sets.
				actual := ctl(removal[index], 0, C.IPC_RMID, 0)
				if actual != 0 && *C.__errno_location() != C.EINVAL { fatal(17) }
			}
		}
		for mode in 0 .. 512 {
			// Every tested operation is net zero. Denial/range/fault paths must not
			// commit any part of the SETALL or semaphore vectors either.
			check(mut t, ctl(ids[mode], 0, C.GETVAL, 0) == 0 && ctl(ids[mode], 1, C.GETVAL, 0) == 0, 1100000 + mode)
			if ctl(ids[mode], 0, C.IPC_RMID, 0) != 0 { fatal(18) }
		}
	}
}

@[export: 'main']
fn fixture_main(argc i32, argv &&char) i32 {
	reference := argc == 2 && unsafe { C.strcmp(argv[1], c'--reference') == 0 }
	C.alarm(180)
	mut totals := Totals{}
	main_cases(mut totals)
	C.printf(c'LINUX SEMPERM SUMMARY: checks=%d failures=%d\n', totals.checks, totals.failures)
	if totals.failures != 0 {
		C.puts(c'LINUX SEMPERM: FAIL')
		C.fflush(unsafe { nil })
		return 1
	}
	C.puts(if reference { c'LINUX SEMPERM REFERENCE: PASS' } else { c'LINUX SEMPERM: PASS' })
	C.fflush(unsafe { nil })
	C.alarm(0)
	for { C.pause() }
	return 0
}
