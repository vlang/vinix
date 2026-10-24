// SPDX-License-Identifier: GPL-2.0-or-later
module seminfofixture

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
	uid u32
	gid u32
	mode u32
}
struct C.semid_ds {
mut:
	sem_perm C.ipc_perm
	sem_nsems u16
}
struct C.seminfo {
mut:
	semmap i32
	semmni i32
	semmns i32
	semmnu i32
	semmsl i32
	semopm i32
	semume i32
	semusz i32
	semvmx i32
	semaem i32
}
struct Totals {
mut:
	checks i32
	failures i32
}
struct CapHeader {
mut:
	version u32
	pid i32
}
struct CapData {
mut:
	effective u32
	permitted u32
	inheritable u32
}

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.strcmp(&char, &char) i32
fn C.memcmp(voidptr, voidptr, usize) i32
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
	C.printf(c'LINUX SEMINFO FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(90)
}
fn check(mut t Totals, good bool, stage int) {
	t.checks++
	if !good {
		t.failures++
		if t.failures <= 12 { C.printf(c'LINUX SEMINFO MISMATCH: stage=%d\n', stage) }
	}
}
fn ctl(id isize, number isize, command isize, argument isize) isize {
	unsafe {
		location := C.__errno_location()
		*location = 0
	}
	return C.syscall(isize(C.SYS_semctl), id, number, command, argument)
}
fn result(mut t Totals, actual isize, expected isize, code i32, stage int) {
	check(mut t, actual == expected && unsafe { *C.__errno_location() } == code, stage)
}
fn create(count int, mode int) isize {
	id := C.syscall(isize(C.SYS_semget), isize(0), isize(count), isize(mode))
	if id < 0 { fatal(1) }
	return id
}
fn usage(mut t Totals, count int, semaphores int, stage int) isize {
	mut info := C.seminfo{}
	highest := ctl(0x7fffffff, -999, 19, isize(unsafe { &info }))
	check(mut t, highest >= 0 && info.semusz == count && info.semaem == semaphores, stage)
	return highest
}
fn slot(id isize) isize {
	mut info := C.seminfo{}
	highest := ctl(0, 0, 3, isize(unsafe { &info }))
	if highest < 0 { return -1 }
	mut ds := C.semid_ds{}
	for index := isize(0); index <= highest; index++ {
		if ctl(index, -999, 20, isize(unsafe { &ds })) == id { return index }
	}
	return -1
}

fn limits(mut t Totals) {
	unsafe {
		mut info := C.seminfo{}
		check(mut t, sizeof(C.seminfo) == 40, 10)
		result(mut t, ctl(0, -999, 3, isize(&info)), 0, 0, 11)
		check(mut t, info.semmni > 0 && info.semmns >= info.semmni && info.semmsl >= 7
			&& info.semopm > 0 && info.semvmx == 32767, 12)
		check(mut t, info.semmap == 1024000000 && info.semmnu == 1024000000
			&& info.semume == 500 && info.semusz == 20 && info.semaem == 32767, 13)
		usage(mut t, 0, 0, 14)
		mut bytes := [56]u8{}
		for command in [isize(3), 19]! {
			C.memset(&bytes[0], 0xa5, sizeof(bytes))
			result(mut t, ctl(0x7fffffff, 0x7fffffff, command, isize(&bytes[8])), 0, 0, 15)
			mut intact := true
			for i in 0 .. 8 { intact = intact && bytes[i] == 0xa5 && bytes[48 + i] == 0xa5 }
			check(mut t, intact, 16)
			for id in [isize(-1), 0, 0x7fffffff]! {
				for address in [isize(0), 1, -1]! {
					result(mut t, ctl(id, -1, command, address), -1, if id < 0 { i32(C.EINVAL) } else { i32(C.EFAULT) }, 17)
				}
			}
			result(mut t, ctl(0, 0, command | 0x100, isize(&info)), -1, C.EINVAL, 18)
			// The kernel imports scalar arguments as signed 32-bit ints.
			result(mut t, ctl(isize(u64(1) << 32), isize(-1), command | isize(u64(1) << 32), isize(&info)), 0, 0, 19)
		}
		page_size := isize(C.getpagesize())
		page := C.syscall(isize(C.SYS_mmap), isize(0), page_size * 2, isize(3), isize(0x22), isize(-1), isize(0))
		if page == -1 || C.syscall(isize(C.SYS_mprotect), page + page_size, page_size, isize(0)) != 0 { fatal(2) }
		for command in [isize(3), 19]! {
			result(mut t, ctl(0, -1, command, page + page_size - 40), 0, 0, 20)
			result(mut t, ctl(0, -1, command, page + page_size - 39), -1, C.EFAULT, 21)
		}
		if C.syscall(isize(C.SYS_munmap), page, page_size * 2) != 0 { fatal(3) }
	}
}

fn inventory(mut t Totals) {
	unsafe {
		mut ids := [4]isize{}
		mut indices := [4]isize{}
		for i in 0 .. 4 { ids[i] = create(2 * i + 1, 0o600) }
		highest := usage(mut t, 4, 16, 30)
		for i in 0 .. 4 {
			indices[i] = slot(ids[i])
			check(mut t, indices[i] >= 0 && indices[i] <= highest, 31)
			mut expected := C.semid_ds{}
			if ctl(ids[i], -1, C.IPC_STAT, isize(&expected)) != 0 { fatal(4) }
			for command in [isize(18), 20]! {
				mut ds := C.semid_ds{}
				result(mut t, ctl(indices[i], -999, command, isize(&ds)), ids[i], 0, 32)
				check(mut t, C.memcmp(&ds, &expected, sizeof(C.semid_ds)) == 0, 33)
				result(mut t, ctl(indices[i], 999, command, 1), -1, C.EFAULT, 34)
				result(mut t, ctl(indices[i], 0, command | 0x100, isize(&ds)), -1, C.EINVAL, 35)
				result(mut t, ctl(indices[i] | isize(u64(1) << 32), -1, command | isize(u64(1) << 32), isize(&ds)), ids[i], 0, 36)
				mut bytes := [120]u8{}
				C.memset(&bytes[0], 0xa5, sizeof(bytes))
				result(mut t, ctl(indices[i], -1, command, isize(&bytes[8])), ids[i], 0, 37)
				mut intact := true
				for j in 0 .. bytes.len {
					if j < 8 || j >= 8 + int(sizeof(C.semid_ds)) { intact = intact && bytes[j] == 0xa5 }
				}
				check(mut t, intact && C.memcmp(&bytes[8], &expected, sizeof(C.semid_ds)) == 0, 38)
			}
		}
		check(mut t, sizeof(C.semid_ds) == $if amd64 { usize(104) } $else { usize(88) }, 3600)
		page_size := isize(C.getpagesize())
		page := C.syscall(isize(C.SYS_mmap), isize(0), page_size * 2, isize(3), isize(0x22), isize(-1), isize(0))
		if page == -1 || C.syscall(isize(C.SYS_mprotect), page + page_size, page_size, isize(0)) != 0 { fatal(13) }
		for command in [isize(18), 20]! {
			result(mut t, ctl(indices[0], -1, command, page + page_size - isize(sizeof(C.semid_ds))), ids[0], 0, 3601)
			result(mut t, ctl(indices[0], -1, command, page + page_size - isize(sizeof(C.semid_ds)) + 1), -1, C.EFAULT, 3602)
		}
		if C.syscall(isize(C.SYS_munmap), page, page_size * 2) != 0 { fatal(14) }
		result(mut t, ctl(ids[1], 0, C.IPC_RMID, 0), 0, 0, 39)
		usage(mut t, 3, 13, 40)
		for command in [isize(18), 20]! {
			for index in [isize(-1), indices[1], highest + 1, 0x7fffffff]! {
				result(mut t, ctl(index, 0, command, 1), -1, C.EINVAL, 41)
			}
		}
		// Deleting an unrelated slot must not renumber surviving sets.
		for i in [0, 2, 3]! { check(mut t, slot(ids[i]) == indices[i], 42) }
		for turn in 0 .. 96 {
			id := create(2, 0o600)
			index := slot(id)
			mut ds := C.semid_ds{}
			check(mut t, index >= 0 && ctl(index, -1, 20, isize(&ds)) == id && ds.sem_nsems == 2, 43)
			usage(mut t, 4, 15, 44)
			result(mut t, ctl(id, 0, C.IPC_RMID, 0), 0, 0, 45)
			result(mut t, ctl(index, 0, 20, isize(&ds)), -1, C.EINVAL, 46)
			usage(mut t, 3, 13, 47)
			check(mut t, slot(ids[3]) == indices[3], 48 + turn)
		}
		for i in [0, 2, 3]! { result(mut t, ctl(ids[i], 0, C.IPC_RMID, 0), 0, 0, 150) }
		result(mut t, usage(mut t, 0, 0, 151), 0, 0, 152)
	}
}

fn credentials(role int) {
	unsafe {
		mut header := CapHeader{ version: 0x20080522 }
		mut caps := [2]CapData{}
		if C.syscall(isize(C.SYS_capget), &header, &caps[0]) != 0 { fatal(5) }
		if C.syscall(isize(C.SYS_setgroups), isize(0), isize(0)) != 0 { fatal(6) }
		gid := if role <= 1 { isize(0) } else { isize(1001) }
		uid := if role == 0 { isize(0) } else { isize(1001) }
		if C.syscall(isize(C.SYS_setresgid), isize(0), gid, isize(0)) != 0
			|| C.syscall(isize(C.SYS_setresuid), isize(0), uid, isize(0)) != 0 { fatal(7) }
		caps[0].effective = if role == 3 { u32(1) << 15 } else { 0 }
		caps[1].effective = 0
		if C.syscall(isize(C.SYS_capset), &header, &caps[0]) != 0 { fatal(8) }
	}
}
fn permissions(mut t Totals) {
	unsafe {
		mut ids := [512]isize{}
		mut indices := [512]isize{}
		for mode in 0 .. 512 { ids[mode] = create(1, mode) }
		mut info := C.seminfo{}
		highest := ctl(0, 0, 19, isize(&info))
		// Enumeration is the only supported way to obtain an index from an ID.
		for i in 0 .. 512 { indices[i] = -1 }
		for index := isize(0); index <= highest; index++ {
			mut ds := C.semid_ds{}
			id := ctl(index, 0, 20, isize(&ds))
			for mode in 0 .. 512 { if id == ids[mode] { indices[mode] = index } }
		}
		for mode in 0 .. 512 { check(mut t, indices[mode] >= 0, 200) }
		for role in 0 .. 4 {
			mut pipe := [2]i32{}
			if C.pipe(&pipe[0]) != 0 { fatal(9) }
			child := C.fork()
			if child < 0 { fatal(10) }
			if child == 0 {
				C.close(pipe[0])
				credentials(role)
				mut local := Totals{}
				for mode in 0 .. 512 {
					read := (mode >> if role == 0 { 6 } else if role == 1 { 3 } else { 0 }) & 4 != 0 || role == 3
					mut ds := C.semid_ds{}
					result(mut local, ctl(indices[mode], -999, 18, isize(&ds)), if read { ids[mode] } else { isize(-1) }, if read { i32(0) } else { i32(C.EACCES) }, 300 + mode)
					result(mut local, ctl(indices[mode], -1, 18, 1), -1, if read { i32(C.EFAULT) } else { i32(C.EACCES) }, 900 + mode)
					result(mut local, ctl(indices[mode], 999, 20, isize(&ds)), ids[mode], 0, 1500 + mode)
					check(mut local, ds.sem_perm.uid == 0 && ds.sem_perm.gid == 0 && ds.sem_perm.mode == u32(mode) && ds.sem_nsems == 1, 2100 + mode)
					result(mut local, ctl(indices[mode], -1, 20, 1), -1, C.EFAULT, 2700 + mode)
				}
				usage(mut local, 512, 512, 3300)
				C.fflush(nil)
				if C.write(pipe[1], &local, sizeof(Totals)) != sizeof(Totals) { C._exit(91) }
				C._exit(0)
			}
			C.close(pipe[1])
			mut local := Totals{}
			if C.read(pipe[0], &local, sizeof(Totals)) != sizeof(Totals) { fatal(11) }
			C.close(pipe[0])
			mut status := i32(-1)
			if C.waitpid(child, &status, 0) != child || status != 0 { fatal(12) }
			t.checks += local.checks
			t.failures += local.failures
		}
		for mode in 0 .. 512 { result(mut t, ctl(ids[mode], 0, C.IPC_RMID, 0), 0, 0, 3400) }
		result(mut t, usage(mut t, 0, 0, 3401), 0, 0, 3402)
	}
}

@[export: 'main']
fn fixture_main(argc i32, argv &&char) i32 {
	C.alarm(180)
	mut totals := Totals{}
	limits(mut totals)
	inventory(mut totals)
	permissions(mut totals)
	C.printf(c'LINUX SEMINFO SUMMARY: checks=%d failures=%d\n', totals.checks, totals.failures)
	reference := argc > 1 && unsafe { C.strcmp(argv[1], c'--reference') == 0 }
	if totals.failures == 0 {
		if reference { C.puts(c'LINUX SEMINFO REFERENCE: PASS') } else { C.puts(c'LINUX SEMINFO: PASS') }
	} else { C.puts(c'LINUX SEMINFO: FAIL') }
	C.fflush(unsafe { nil })
	if totals.failures != 0 { return 1 }
	C.alarm(0)
	for { C.pause() }
	return 0
}
