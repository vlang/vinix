// SPDX-License-Identifier: GPL-2.0-or-later
module semnsfixture

#include <errno.h>
#include <alloca.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/sem.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.semid_ds { mut: sem_nsems u16 }
struct C.seminfo { mut: semusz i32 semaem i32 }
@[packed]
struct Operation { number u16 operation i16 flags i16 }
struct Duration { seconds i64 nanoseconds i64 }
struct Totals { mut: checks i32 failures i32 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 tainted u64 }
fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.strcmp(&char, &char) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C.usleep(u32) i32
fn C.fork() i32
fn C.pipe(&i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.write(i32, voidptr, usize) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.alloca(usize) voidptr

fn fatal(stage int) {
	C.printf(c'LINUX SEMNS FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut t Totals, good bool, stage int) {
	t.checks++
	if !good { t.failures++; if t.failures <= 12 { C.printf(c'LINUX SEMNS MISMATCH: stage=%d\n', stage) } }
}
fn clear_errno() {
	unsafe { p := C.__errno_location(); *p = 0 }
}
fn ctl(id isize, command isize, argument isize) isize {
	clear_errno()
	return C.syscall(isize(C.SYS_semctl), id, isize(0), command, argument)
}
fn result(mut t Totals, actual isize, expected isize, code i32, stage int) {
	check(mut t, actual == expected && unsafe { *C.__errno_location() } == code, stage)
}
fn create(key isize, count int, flags int) isize {
	return C.syscall(isize(C.SYS_semget), key, isize(count), isize(flags))
}
fn usage(mut t Totals, count int, semaphores int, stage int) {
	mut info := C.seminfo{}
	highest := ctl(0, 19, isize(unsafe { &info }))
	check(mut t, highest >= 0 && info.semusz == count && info.semaem == semaphores, stage)
}
fn enter(fd i32) {
	if C.syscall(isize(C.SYS_setns), isize(fd), isize(0x08000000)) != 0 { fatal(1) }
}
fn unshare() {
	if C.syscall(isize(C.SYS_unshare), isize(0x08000000)) != 0 { fatal(2) }
}
fn namespace_fd(pid i32) i32 {
	mut path := [64]char{}
	C.snprintf(unsafe { &path[0] }, sizeof(path), c'/proc/%d/ns/ipc', pid)
	fd := C.open(unsafe { &path[0] }, 0)
	if fd < 0 { fatal(3) }; return fd
}
fn send(fd i32, data voidptr, size usize) {
	if C.write(fd, data, size) != isize(size) { fatal(4) }
}
fn receive(fd i32, data voidptr, size usize) {
	if C.read(fd, data, size) != isize(size) { fatal(5) }
}
fn reap(pid i32) {
	mut status := i32(-1)
	if C.waitpid(pid, unsafe { &status }, 0) != pid || status != 0 { fatal(6) }
}
fn foreign(mut t Totals, id isize, stage int) {
	unsafe {
		mut ds := C.semid_ds{}
		mut values := [3]u16{}
		for command in [isize(2), 11, 12, 13, 14, 15]! {
			argument := if command == 1 || command == 2 { isize(&ds) }
				else if command == 13 || command == 17 { isize(&values[0]) } else { isize(0) }
			result(mut t, ctl(id, command, argument), -1, C.EINVAL, stage + int(command))
		}
		mut op := Operation{flags: 0o4000}; mut timeout := Duration{}
		clear_errno()
		result(mut t, C.syscall(isize(C.SYS_semop), id, &op, isize(1)), -1, C.EINVAL, stage + 21)
		clear_errno()
		result(mut t, C.syscall(isize(C.SYS_semtimedop), id, &op, isize(1), &timeout), -1, C.EINVAL, stage + 22)
		for command in [isize(18), 20]! {
			result(mut t, ctl(0, command, isize(&ds)), -1, C.EINVAL, stage + int(command))
		}
	}
}
fn isolation(mut t Totals, parent_fd i32, parent_id isize) {
	unsafe {
		mut ready := [2]i32{}; mut proceed := [2]i32{}
		if C.pipe(&ready[0]) != 0 || C.pipe(&proceed[0]) != 0 { fatal(7) }
		child := C.fork(); if child < 0 { fatal(8) }
		if child == 0 {
			C.close(ready[0]); C.close(proceed[1]); mut local := Totals{}
			result(mut local, ctl(parent_id, 12, 0), 7, 0, 10)
			unshare(); usage(mut local, 0, 0, 11)
			foreign(mut local, parent_id, 20)
			clear_errno()
			result(mut local, create(0x534e5301, 0, 0), -1, C.ENOENT, 50)
			mut id := create(0x534e5301, 3, 0o3600)
			check(mut local, id >= 0, 51)
			// Continue on the broken baseline after its global key collision.
			if id < 0 { id = create(0, 3, 0o600) }; if id < 0 { fatal(9) }
			usage(mut local, 1, 3, 52)
			mut ds := C.semid_ds{}
			result(mut local, ctl(0, 20, isize(&ds)), id, 0, 53)
			check(mut local, ds.sem_nsems == 3, 54)
			result(mut local, ctl(id, 16, 11), 0, 0, 55)
			result(mut local, ctl(id, 12, 0), 11, 0, 56)
			grandchild := C.fork(); if grandchild < 0 { fatal(10) }
			if grandchild == 0 {
				if ctl(id, 12, 0) != 11 || ctl(id, 16, 13) != 0 { C._exit(1) }; C._exit(0)
			}
			reap(grandchild); result(mut local, ctl(id, 12, 0), 13, 0, 57)
			send(ready[1], &id, sizeof(id))
			mut token := u8(0); receive(proceed[0], &token, 1)
			original := namespace_fd(i32(C.syscall(isize(C.SYS_getpid))))
			unshare(); usage(mut local, 0, 0, 58); foreign(mut local, id, 60)
			enter(original); result(mut local, ctl(id, 12, 0), 13, 0, 90)
			C.close(original); C.fflush(nil); send(ready[1], &local, sizeof(local)); C._exit(0)
		}
		C.close(ready[1]); C.close(proceed[0])
		mut id := isize(-1); receive(ready[0], &id, sizeof(id))
		retained := namespace_fd(child)
		mut token := u8(1); send(proceed[1], &token, 1)
		mut local := Totals{}; receive(ready[0], &local, sizeof(local)); reap(child)
		t.checks += local.checks; t.failures += local.failures
		C.close(ready[0]); C.close(proceed[1])
		result(mut t, ctl(parent_id, 12, 0), 7, 0, 100); usage(mut t, 1, 2, 101)
		// nsfs retains objects after their creating process exits.
		enter(retained); usage(mut t, 1, 3, 102)
		result(mut t, ctl(id, 12, 0), 13, 0, 103)
		check(mut t, create(0x534e5301, 0, 0) == id, 104)
		C.close(retained); result(mut t, ctl(id, 12, 0), 13, 0, 105)
		enter(parent_fd); result(mut t, ctl(parent_id, 12, 0), 7, 0, 106); usage(mut t, 1, 2, 107)
	}
}
fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination)
		*counts = Slabs{}; mut data := [16384]char{}
		length := C.pread(fd, &data[0], sizeof(data) - 1, 0)
		if length <= 0 || length >= isize(sizeof(data) - 1) { return false }
		mut position := 0; mut large := false; mut guarded := false
		for position < int(length) {
			mut size := u64(0); mut duplicate := u64(0); mut live := u64(0); mut pages := u64(0)
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate, &live, &pages) == 4 {
				if counts.rows >= 32 || size != duplicate { return false }
				counts.sizes[counts.rows] = size; counts.live[counts.rows] = live; counts.rows++
			} else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 { large = true }
			else if C.sscanf(&data[position], c'# written after free %lu', &counts.tainted) == 1 { guarded = true }
			for position < int(length) && data[position] != 10 { position++ }; position++
		}
		return counts.rows > 0 && large && guarded
	}
}
fn retained_namespace() i32 {
	unsafe {
		mut ready := [2]i32{}; mut proceed := [2]i32{}
		if C.pipe(&ready[0]) != 0 || C.pipe(&proceed[0]) != 0 { fatal(11) }
		child := C.fork(); if child < 0 { fatal(12) }
		if child == 0 {
			C.close(ready[0]); C.close(proceed[1]); unshare()
			mut token := u8(1); send(ready[1], &token, 1); receive(proceed[0], &token, 1); C._exit(0)
		}
		C.close(ready[1]); C.close(proceed[0])
		mut token := u8(0); receive(ready[0], &token, 1)
		fd := namespace_fd(child); send(proceed[1], &token, 1); reap(child)
		C.close(ready[0]); C.close(proceed[1]); return fd
	}
}
fn teardown(mut t Totals, parent_fd i32, reference bool) {
	observer := if reference { i32(-1) } else { C.open(c'/proc/slabinfo', 0) }
	if !reference && observer < 0 { fatal(13) }
	for cycle in 0 .. 2 {
		fd := retained_namespace()
		before := unsafe { &Slabs(C.alloca(sizeof(Slabs))) }
		occupied := unsafe { &Slabs(C.alloca(sizeof(Slabs))) }
		after := unsafe { &Slabs(C.alloca(sizeof(Slabs))) }
		if !reference && (!snapshot(observer, before) || !snapshot(observer, before)) { fatal(14) }
		enter(fd); usage(mut t, 0, 0, 110)
		for i in 0 .. 200 { check(mut t, create(0, 32, 0o600) >= 0, 111 + i) }
		usage(mut t, 200, 6400, 312); enter(parent_fd)
		if !reference && !snapshot(observer, occupied) { fatal(15) }
		C.close(fd); C.usleep(200000)
		if !reference && !snapshot(observer, after) { fatal(16) }
		// First cycle warms array capacity; the measured namespace and nsfs
		// descriptor already exist at the second cycle's initial snapshot.
		if cycle == 1 && !reference {
			mut grew := false; mut flat := before.rows == after.rows && after.large <= before.large && after.tainted == before.tainted
			for i in 0 .. int(before.rows) { unsafe {
				if occupied.live[i] >= before.live[i] + 200 { grew = true }
				flat = flat && before.sizes[i] == after.sizes[i] && after.live[i] <= before.live[i]
				C.printf(c'LINUX SEMNS SLAB: size=%lu before=%lu occupied=%lu after=%lu\n', before.sizes[i], before.live[i], occupied.live[i], after.live[i])
			} }
			C.printf(c'LINUX SEMNS STORAGE: arrays=200 semaphores=6400 big_pages=%lu/%lu/%lu %s\n', before.large, occupied.large, after.large, if flat && grew { &char(c'PASS') } else { &char(c'FAIL') })
			check(mut t, flat && grew, 313)
		}
	}
	if observer >= 0 { C.close(observer) }
}
@[export: 'main']
fn fixture_main(argc i32, argv &&char) i32 {
	C.alarm(180)
	reference := argc > 1 && unsafe { C.strcmp(argv[1], c'--reference') == 0 }
	parent_fd := namespace_fd(i32(C.syscall(isize(C.SYS_getpid))))
	parent_id := create(0x534e5301, 2, 0o3600)
	if parent_id < 0 || ctl(parent_id, 16, 7) != 0 { fatal(17) }
	mut t := Totals{}
	isolation(mut t, parent_fd, parent_id); teardown(mut t, parent_fd, reference)
	result(mut t, ctl(parent_id, 0, 0), 0, 0, 400); C.close(parent_fd)
	C.printf(c'LINUX SEMNS SUMMARY: checks=%d failures=%d\n', t.checks, t.failures)
	if t.failures == 0 { C.puts(if reference { c'LINUX SEMNS REFERENCE: PASS' } else { c'LINUX SEMNS: PASS' }) }
	else { C.puts(c'LINUX SEMNS: FAIL') }
	C.fflush(unsafe { nil }); if t.failures != 0 { return 1 }
	C.alarm(0); for { C.pause() }; return 0
}
