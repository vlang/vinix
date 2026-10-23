// SPDX-License-Identifier: GPL-2.0-or-later
module semmetafixture

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/sem.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.ipc_perm {
mut:
	__ipc_perm_key i32
	uid            u32
	gid            u32
	cuid           u32
	cgid           u32
	mode           u32
}

struct C.semid_ds {
mut:
	sem_perm  C.ipc_perm
	sem_otime i64
	sem_ctime i64
	sem_nsems u16
}

struct C.sembuf {
mut:
	sem_num u16
	sem_op  i16
	sem_flg i16
}

struct CapHeader {
mut:
	version u32
	pid     i32
}

struct CapData {
mut:
	effective   u32
	permitted   u32
	inheritable u32
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
fn C.memset(voidptr, int, usize) voidptr
fn C.alarm(u32) u32
fn C.pause() i32
fn C.fork() i32
fn C.pipe(&i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.getpagesize() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)

fn fatal(stage int) {
	C.printf(c'LINUX SEMMETA FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(90)
}

fn check(mut t Totals, good bool, stage int) {
	t.checks++
	if !good {
		t.failures++
		if t.failures <= 12 { C.printf(c'LINUX SEMMETA MISMATCH: stage=%d\n', stage) }
	}
}

fn ctl(id isize, number isize, command isize, argument isize) isize {
	unsafe {
		location := C.__errno_location()
		*location = 0
	}
	return C.syscall(isize(C.SYS_semctl), id, number, command, argument)
}

fn result(mut t Totals, actual isize, code i32, stage int) {
	check(mut t, actual == if code == 0 { isize(0) } else { isize(-1) }
		&& unsafe { *C.__errno_location() } == code, stage)
}

fn clock_seconds(clock isize) i64 {
	mut stamp := Stamp{}
	if C.syscall(isize(C.SYS_clock_gettime), clock, unsafe { &stamp }) != 0 { fatal(1) }
	return stamp.sec
}

fn now() i64 {
	return clock_seconds(0)
}

fn next_second() i64 {
	start := now()
	// Linux semaphore timestamps sample coarse realtime. Wait for that clock
	// to cross the boundary before asserting a new whole-second timestamp.
	for clock_seconds(5) <= start {
	}
	return clock_seconds(5)
}

fn stat(id isize, mut ds C.semid_ds) bool {
	return ctl(id, -123, C.IPC_STAT, isize(unsafe { &ds })) == 0
}

fn metadata(mut t Totals) {
	unsafe {
		mut ds := C.semid_ds{}
		size := isize(sizeof(C.semid_ds))
		expected := $if amd64 { isize(104) } $else { isize(88) }
		ctime_offset := $if amd64 { isize(64) } $else { isize(56) }
		count_offset := $if amd64 { isize(80) } $else { isize(64) }
		check(mut t, size == expected && sizeof(C.ipc_perm) == 48, 10)
		check(mut t, isize(&ds.sem_otime) - isize(&ds) == 48
			&& isize(&ds.sem_ctime) - isize(&ds) == ctime_offset
			&& isize(&ds.sem_nsems) - isize(&ds) == count_offset, 11)
		before := clock_seconds(5)
		id := C.syscall(isize(C.SYS_semget), isize(0x534d4554), isize(3), isize(0o1600))
		if id < 0 { fatal(2) }
		check(mut t, stat(id, mut ds), 12)
		check(mut t, ds.sem_perm.__ipc_perm_key == i32(0x534d4554)
			&& ds.sem_perm.uid == 0 && ds.sem_perm.gid == 0
			&& ds.sem_perm.cuid == 0 && ds.sem_perm.cgid == 0
			&& ds.sem_perm.mode == 0o600 && ds.sem_nsems == 3
			&& ds.sem_otime == 0 && ds.sem_ctime >= before && ds.sem_ctime <= now(), 13)
		// A canary covers both ends and all ABI padding is cleared.
		mut bytes := [120]u8{}
		C.memset(&bytes[0], 0xa5, sizeof(bytes))
		result(mut t, ctl(id, 999, C.IPC_STAT, isize(&bytes[8])), 0, 14)
		mut clean := true
		for i in 0 .. bytes.len {
			if i < 8 || i >= 8 + int(size) { clean = clean && bytes[i] == 0xa5 }
		}
		for i in [28, 29, 30, 31, 32, 39, 40, 47]! { clean = clean && bytes[8 + i] == 0 }
		check(mut t, clean, 15)
		mark := next_second()
		result(mut t, ctl(id, 1, C.SETVAL, 7), 0, 16)
		check(mut t, stat(id, mut ds) && ds.sem_ctime >= mark && ds.sem_otime == 0, 17)
		old_ctime := ds.sem_ctime
		mark2 := next_second()
		mut op := C.sembuf{ sem_num: 0, sem_op: 0 }
		result(mut t, C.syscall(isize(C.SYS_semop), id, &op, isize(1)), 0, 18)
		check(mut t, stat(id, mut ds) && ds.sem_otime >= mark2 && ds.sem_ctime == old_ctime, 19)
		old_otime := ds.sem_otime
		mut values := [u16(2), 3, 4]!
		mark3 := next_second()
		result(mut t, ctl(id, -1, C.SETALL, isize(&values[0])), 0, 20)
		check(mut t, stat(id, mut ds) && ds.sem_ctime >= mark3 && ds.sem_otime == old_otime, 21)
		// Ignored input fields cannot overwrite creator/key/count/timestamps.
		C.memset(&ds, 0x7f, sizeof(C.semid_ds))
		ds.sem_perm.uid = 1002
		ds.sem_perm.gid = 2002
		ds.sem_perm.mode = 0xffff01a4 // low nine bits: 0644
		mark4 := next_second()
		result(mut t, ctl(id, -999, C.IPC_SET, isize(&ds)), 0, 22)
		check(mut t, stat(id, mut ds) && ds.sem_perm.uid == 1002 && ds.sem_perm.gid == 2002
			&& ds.sem_perm.cuid == 0 && ds.sem_perm.cgid == 0
			&& ds.sem_perm.mode == 0o644 && ds.sem_perm.__ipc_perm_key == i32(0x534d4554)
			&& ds.sem_nsems == 3 && ds.sem_otime == old_otime && ds.sem_ctime >= mark4, 23)
		// The full native input size must be readable, even unused trailing bytes.
		page_size := isize(C.getpagesize())
		page := C.syscall(isize(C.SYS_mmap), isize(0), 2 * page_size, isize(C.PROT_READ | C.PROT_WRITE),
			isize(C.MAP_PRIVATE | C.MAP_ANONYMOUS), isize(-1), isize(0))
		if page_size <= 0 || page == -1 || C.syscall(isize(C.SYS_mprotect), page + page_size, page_size, isize(C.PROT_NONE)) != 0 {
			fatal(3)
		}
		full := &C.semid_ds(page + page_size - size)
		*full = ds
		result(mut t, ctl(id, 0, C.IPC_SET, isize(full)), 0, 24)
		result(mut t, ctl(id, 0, C.IPC_SET, isize(full) + 1), C.EFAULT, 25)
		result(mut t, ctl(id, 0, C.IPC_STAT, isize(full) + 1), C.EFAULT, 26)
		for bad in [isize(0), 1, page + page_size]! {
			result(mut t, ctl(-1, -1, C.IPC_SET, bad), C.EINVAL, 27)
			result(mut t, ctl(0x7fffffff, -1, C.IPC_SET, bad), C.EFAULT, 28)
			result(mut t, ctl(0x7fffffff, -1, C.IPC_STAT, bad), C.EINVAL, 29)
			result(mut t, ctl(id, -1, C.IPC_SET, bad), C.EFAULT, 30)
			result(mut t, ctl(id, -1, C.IPC_STAT, bad), C.EFAULT, 31)
		}
		for invalid in [u32(0xffffffff), 0xfffffffe]! {
			ds.sem_perm.uid = invalid
			ds.sem_perm.gid = 2002
			result(mut t, ctl(id, 0, C.IPC_SET, isize(&ds)), if invalid == u32(-1) {
				i32(C.EINVAL)
			} else {
				i32(0)
			}, 32)
			ds.sem_perm.uid = 1002
			ds.sem_perm.gid = invalid
			result(mut t, ctl(id, 0, C.IPC_SET, isize(&ds)), if invalid == u32(-1) {
				i32(C.EINVAL)
			} else {
				i32(0)
			}, 33)
		}
		result(mut t, ctl(id, 0, C.IPC_STAT | 0x100, isize(&ds)), C.EINVAL, 34)
		result(mut t, ctl(id, 0, C.IPC_SET | 0x100, isize(&ds)), C.EINVAL, 35)
		result(mut t, ctl(id, 0, C.IPC_RMID, 0), 0, 36)
		result(mut t, ctl(id, 0, C.IPC_STAT, isize(&ds)), C.EINVAL, 37)
		result(mut t, ctl(id, 0, C.IPC_SET, isize(&ds)), C.EINVAL, 38)
		if C.syscall(isize(C.SYS_munmap), page, 2 * page_size) != 0 { fatal(4) }
	}
}

fn credentials(role int) {
	unsafe {
		mut header := CapHeader{ version: 0x20080522 }
		mut caps := [2]CapData{}
		if C.syscall(isize(C.SYS_capget), &header, &caps[0]) != 0 { fatal(5) }
		mut group := u32(if role == 2 {
			2001
		} else if role == 3 {
			2002
		} else {
			9999
		})
		if C.syscall(isize(C.SYS_setgroups), isize(1), &group) != 0
			|| C.syscall(isize(C.SYS_setresgid), isize(0), isize(9999), isize(0)) != 0 {
			fatal(6)
		}
		uid := if role == 0 {
			isize(1001)
		} else if role == 1 {
			isize(1002)
		} else {
			isize(1003)
		}
		if C.syscall(isize(C.SYS_setresuid), isize(0), uid, isize(0)) != 0 { fatal(7) }
		caps[0].effective = if role == 5 {
			u32(1) << 15
		} else if role == 6 {
			u32(1) << 21
		} else {
			0
		}
		caps[1].effective = 0
		if C.syscall(isize(C.SYS_capset), &header, &caps[0]) != 0 { fatal(8) }
	}
}

fn exercise(mut t Totals, ids &isize, role int) {
	unsafe {
		credentials(role)
		owner := role in [0, 1]
		for mode in 0 .. 512 {
			id := ids[mode]
			stage := 1000 + role * 10000 + mode * 10
			read := (if owner {
				mode >> 6
			} else if role in [2, 3] {
				mode >> 3
			} else {
				mode
			}) & 4 != 0 || role == 5
			rcode := if read { i32(0) } else { i32(C.EACCES) }
			mut ds := C.semid_ds{}
			result(mut t, ctl(id, -999, C.IPC_STAT, isize(&ds)), rcode, stage)
			check(mut t, !read || (ds.sem_perm.uid == 1002 && ds.sem_perm.gid == 2002
				&& ds.sem_perm.cuid == 1001 && ds.sem_perm.cgid == 2001
				&& ds.sem_perm.mode == u32(mode) && ds.sem_nsems == 2), stage + 1)
			result(mut t, ctl(id, 999, C.IPC_STAT, 1), if read {
				i32(C.EFAULT)
			} else {
				i32(C.EACCES)
			}, stage + 2)
			ds.sem_perm.uid = u32(-1)
			ds.sem_perm.gid = u32(-1)
			allowed := owner || role == 6
			result(mut t, ctl(id, 999, C.IPC_SET, isize(&ds)), if allowed {
				i32(C.EINVAL)
			} else {
				i32(C.EPERM)
			}, stage + 3)
			result(mut t, ctl(id, 999, C.IPC_SET, 1), C.EFAULT, stage + 4)
			// Owners can assign arbitrary valid IDs without CAP_CHOWN.
			ds.sem_perm.uid = 1002
			ds.sem_perm.gid = 2002
			ds.sem_perm.mode = u32(mode) | 0xfffffe00
			result(mut t, ctl(id, -999, C.IPC_SET, isize(&ds)), if allowed {
				i32(0)
			} else {
				i32(C.EPERM)
			}, stage + 5)
			clear := ctl(id, 0, C.GETVAL, 0)
			check(mut t, clear == if read { isize(0) } else { isize(-1) }
				&& *C.__errno_location() == rcode, stage + 6)
			// Creator and new owner retain independent removal authority.
			result(mut t, ctl(id, -999, C.IPC_RMID, 0), if allowed { i32(0) } else { i32(C.EPERM) }, stage + 7)
		}
	}
}

fn permissions(mut t Totals) {
	unsafe {
		for role in 0 .. 7 {
			mut ids := [512]isize{}
			if C.syscall(isize(C.SYS_setresgid), isize(-1), isize(2001), isize(-1)) != 0
				|| C.syscall(isize(C.SYS_setresuid), isize(-1), isize(1001), isize(-1)) != 0 {
				fatal(9)
			}
			for mode in 0 .. 512 {
				ids[mode] = C.syscall(isize(C.SYS_semget), isize(C.IPC_PRIVATE), isize(2), isize(mode))
				if ids[mode] < 0 { fatal(10) }
				mut ds := C.semid_ds{}
				ds.sem_perm.uid = 1002
				ds.sem_perm.gid = 2002
				ds.sem_perm.mode = u32(mode)
				// A broken baseline does not abort: its semantic failure is counted in the child.
				ctl(ids[mode], 0, C.IPC_SET, isize(&ds))
			}
			if C.syscall(isize(C.SYS_setresuid), isize(-1), isize(0), isize(-1)) != 0
				|| C.syscall(isize(C.SYS_setresgid), isize(-1), isize(0), isize(-1)) != 0 {
				fatal(11)
			}
			mut pipe := [2]i32{}
			if C.pipe(&pipe[0]) != 0 { fatal(12) }
			child := C.fork()
			if child < 0 { fatal(13) }
			if child == 0 {
				C.close(pipe[0])
				mut local := Totals{}
				exercise(mut local, &ids[0], role)
				C.fflush(nil)
				if C.write(pipe[1], &local, sizeof(Totals)) != sizeof(Totals) { C._exit(91) }
				C._exit(0)
			}
			C.close(pipe[1])
			mut local := Totals{}
			if C.read(pipe[0], &local, sizeof(Totals)) != sizeof(Totals) { fatal(14) }
			C.close(pipe[0])
			mut status := i32(-1)
			if C.waitpid(child, &status, 0) != child || status != 0 { fatal(15) }
			t.checks += local.checks
			t.failures += local.failures
			for id in ids { ctl(id, 0, C.IPC_RMID, 0) }
		}
	}
}

@[export: 'main']
fn fixture_main(argc i32, argv &&char) i32 {
	reference := argc > 1 && unsafe { C.strcmp(argv[1], c'--reference') == 0 }
	C.alarm(150)
	mut totals := Totals{}
	metadata(mut totals)
	permissions(mut totals)
	C.printf(c'LINUX SEMMETA SUMMARY: checks=%d failures=%d\n', totals.checks, totals.failures)
	if totals.failures != 0 {
		C.puts(c'LINUX SEMMETA: FAIL')
		C.fflush(unsafe { nil })
		return 1
	}
	C.puts(if reference { c'LINUX SEMMETA REFERENCE: PASS' } else { c'LINUX SEMMETA: PASS' })
	C.fflush(unsafe { nil })
	C.alarm(0)
	for { C.pause() }
	return 0
}
