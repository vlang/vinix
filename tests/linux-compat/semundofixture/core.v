// SPDX-License-Identifier: GPL-2.0-or-later
module semundofixture

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/sem.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

@[packed]
struct SemOp { number u16 adjustment i16 flags i16 }
struct C.timespec { tv_sec isize tv_nsec isize }
struct C.ipc_perm { mut: mode u32 }
struct C.semid_ds { mut: sem_perm C.ipc_perm sem_otime i64 sem_ctime i64 }
struct Totals { mut: checks i32 failures i32 }
struct Outcome { value isize code i32 }
struct State { values [2]isize pids [2]isize otime i64 ctime i64 }

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.strcmp(&char, &char) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.pipe(&i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.usleep(u32) i32
fn C.geteuid() u32
fn C.setuid(u32) i32
fn C._exit(i32)

fn fatal(stage int) {
	C.printf(c'LINUX SEMUNDO FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(90)
}

fn check(mut t Totals, good bool, stage int) {
	t.checks++
	if !good {
		t.failures++
		if t.failures <= 20 { C.printf(c'LINUX SEMUNDO MISMATCH: stage=%d\n', stage) }
	}
}

fn ctl(id i32, number int, command int, argument isize) isize {
	location := C.__errno_location()
	unsafe { *location = 0 }
	return C.syscall(isize(C.SYS_semctl), isize(id), isize(number), isize(command), argument)
}

fn create() i32 {
	id := i32(C.syscall(isize(C.SYS_semget), isize(C.IPC_PRIVATE), isize(2), isize(0o600)))
	if id < 0 { fatal(1) }
	return id
}

fn remove(id i32) { if ctl(id, 0, C.IPC_RMID, 0) != 0 { fatal(2) } }
fn set_value(id i32, number int, value int) {
	if ctl(id, number, C.SETVAL, isize(value)) != 0 { fatal(3) }
}

fn invoke(method int, id i32, ops voidptr, count u64, timeout voidptr) Outcome {
	location := C.__errno_location()
	unsafe { *location = 0 }
	value := if method == 0 {
		C.syscall(isize(C.SYS_semop), isize(id), ops, count)
	} else { C.syscall(isize(C.SYS_semtimedop), isize(id), ops, count, timeout) }
	return Outcome{ value, unsafe { *C.__errno_location() } }
}

fn expect(mut t Totals, actual Outcome, wanted int, stage int) {
	check(mut t, actual.value == if wanted == 0 { isize(0) } else { isize(-1) }
		&& actual.code == wanted, stage)
	if actual.code != wanted && t.failures <= 20 {
		C.printf(c'LINUX SEMUNDO DETAIL: stage=%d result=%ld/%d expected=%d\n', stage, actual.value, actual.code, wanted)
	}
}

fn state(id i32) State {
	mut metadata := C.semid_ds{}
	if ctl(id, 0, C.IPC_STAT, isize(unsafe { &metadata })) != 0 { fatal(4) }
	return State{
		values: [ctl(id, 0, C.GETVAL, 0), ctl(id, 1, C.GETVAL, 0)]!
		pids: [ctl(id, 0, C.GETPID, 0), ctl(id, 1, C.GETPID, 0)]!
		otime: metadata.sem_otime
		ctime: metadata.sem_ctime
	}
}

fn unchanged(mut t Totals, id i32, before State) {
	after := state(id)
	check(mut t, after.values == before.values, 100)
	check(mut t, after.pids == before.pids, 101)
	check(mut t, after.otime == before.otime && after.ctime == before.ctime, 102)
	for number in 0 .. 2 {
		check(mut t, ctl(id, number, C.GETNCNT, 0) == 0 && ctl(id, number, C.GETZCNT, 0) == 0, 103)
	}
}

fn refusals(mut t Totals) {
	unsafe {
		id := create()
		set_value(id, 0, 1)
		set_value(id, 1, 2)
		before := state(id)
		for method in 0 .. 4 {
			mut timeout := C.timespec{ tv_sec: if method == 3 { 1 } else { 0 } }
			pointer := if method == 1 { nil } else { voidptr(&timeout) }
			for adjustment in [i16(-32768), -2, -1, 1, 32767]! {
				for flags in [i16(C.SEM_UNDO), i16(C.SEM_UNDO | C.IPC_NOWAIT), i16(C.SEM_UNDO | 0x2000), i16(-1)]! {
					mut op := SemOp{ adjustment: adjustment flags: flags }
					expect(mut t, invoke(method, id, &op, 1, pointer), C.EOPNOTSUPP, 110)
					unchanged(mut t, id, before)
				}
			}
			// A normal operation before an undo operation must not be committed.
			// Net-zero undo vectors still require unsupported undo bookkeeping.
			for position in 0 .. 3 {
				mut ops := [SemOp{ adjustment: 1 }, SemOp{ adjustment: 1 }, SemOp{ adjustment: 1 }]!
				ops[position] = SemOp{ number: 1 adjustment: -1 flags: i16(C.SEM_UNDO) }
				expect(mut t, invoke(method, id, &ops[0], 3, pointer), C.EOPNOTSUPP, 111)
				unchanged(mut t, id, before)
			}
			mut cancel := [SemOp{ adjustment: -1 flags: i16(C.SEM_UNDO) }, SemOp{ adjustment: 1 flags: i16(C.SEM_UNDO) }]!
			expect(mut t, invoke(method, id, &cancel[0], 2, pointer), C.EOPNOTSUPP, 112)
			unchanged(mut t, id, before)
		}
		// Repeated rejection also exercises timed-operation cleanup and IPC pins.
		mut op := SemOp{ adjustment: 1 flags: i16(C.SEM_UNDO) }
		mut zero := C.timespec{}
		for _ in 0 .. 200 { expect(mut t, invoke(1, id, &op, 1, &zero), C.EOPNOTSUPP, 113) }
		unchanged(mut t, id, before)
		remove(id)
	}
}

fn common(mut t Totals) {
	unsafe {
		id := create()
		stale := create()
		remove(stale)
		mut zero := C.timespec{}
		mut bad := C.timespec{ tv_nsec: 1000000000 }
		mut undo := SemOp{ adjustment: 1 flags: i16(C.SEM_UNDO) }
		for method in 0 .. 2 {
			expect(mut t, invoke(method, id, nil, 1, &zero), C.EFAULT, 200)
			expect(mut t, invoke(method, id, &undo, 0, &zero), C.EINVAL, 201)
			// Above both the native vector limit (32) and Linux's default (500).
			expect(mut t, invoke(method, id, &undo, 501, &zero), C.E2BIG, 202)
			expect(mut t, invoke(method, stale, &undo, 1, &zero), C.EINVAL, 203)
			expect(mut t, invoke(method, -1, &undo, 1, &zero), C.EINVAL, 204)
			for position in 0 .. 2 {
				mut ops := [undo, undo]!
				ops[position] = SemOp{ number: 2 adjustment: 1 flags: i16(C.SEM_UNDO) }
				expect(mut t, invoke(method, id, &ops[0], 2, &zero), C.EFBIG, 205)
			}
			// Zero operations create no undo adjustment, including unknown flags.
			for flags in [i16(C.SEM_UNDO), i16(-1)]! {
				mut op := SemOp{ flags: flags }
				expect(mut t, invoke(method, id, &op, 1, &zero), 0, 206)
				set_value(id, 0, 1)
				op = SemOp{ flags: i16(C.SEM_UNDO | C.IPC_NOWAIT) }
				expect(mut t, invoke(method, id, &op, 1, &zero), C.EAGAIN, 207)
				set_value(id, 0, 0)
			}
		}
		expect(mut t, invoke(1, id, &undo, 1, voidptr(1)), C.EFAULT, 208)
		expect(mut t, invoke(1, id, &undo, 1, &bad), C.EINVAL, 209)
		expect(mut t, invoke(1, id, nil, 1, &bad), C.EFAULT, 210)
		mut wait_zero := SemOp{ flags: i16(C.SEM_UNDO) }
		set_value(id, 0, 1)
		expect(mut t, invoke(1, id, &wait_zero, 1, &zero), C.EAGAIN, 211)
		mut normal := SemOp{ adjustment: 1 flags: i16(0x2000) }
		expect(mut t, invoke(0, id, &normal, 1, nil), 0, 212)
		check(mut t, ctl(id, 0, C.GETVAL, 0) == 2, 213)
		if C.geteuid() != 0 {
			mut metadata := C.semid_ds{}
			if ctl(id, 0, C.IPC_STAT, isize(&metadata)) != 0 { fatal(5) }
			metadata.sem_perm.mode = 0
			if ctl(id, 0, C.IPC_SET, isize(&metadata)) != 0 { fatal(6) }
			for method in 0 .. 2 { expect(mut t, invoke(method, id, &undo, 1, &zero), C.EACCES, 214) }
		}
		remove(id)
	}
}

fn byte(fd i32, sending bool) {
	mut value := u8(1)
	actual := if sending { C.write(fd, &value, 1) } else { C.read(fd, &value, 1) }
	if actual != 1 || value != 1 { fatal(7) }
}

fn reap(pid i32, mut t Totals) {
	mut status := i32(-1)
	check(mut t, C.waitpid(pid, &status, 0) == pid && status == 0, 300)
}

fn exit_adjustment(reference bool, mut t Totals) {
	unsafe {
		for adjustment in [i16(-1), i16(1)]! {
			id := create()
			set_value(id, 0, 2)
			mut ready := [2]i32{}
			mut release := [2]i32{}
			if C.pipe(&ready[0]) != 0 || C.pipe(&release[0]) != 0 { fatal(8) }
			C.fflush(nil)
			pid := C.fork()
			if pid < 0 { fatal(9) }
			if pid == 0 {
				C.close(ready[0]); C.close(release[1])
				mut op := SemOp{ adjustment: adjustment flags: i16(C.SEM_UNDO) }
				mut child := Totals{}
				expect(mut child, invoke(0, id, &op, 1, nil), if reference { 0 } else { C.EOPNOTSUPP }, 301)
				byte(ready[1], true); byte(release[0], false)
				C.fflush(nil)
				C._exit(if child.failures == 0 { 0 } else { 1 })
			}
			C.close(ready[1]); C.close(release[0])
			byte(ready[0], false)
			check(mut t, ctl(id, 0, C.GETVAL, 0) == if reference { isize(2 + adjustment) } else { isize(2) }, 302)
			byte(release[1], true)
			reap(pid, mut t)
			check(mut t, ctl(id, 0, C.GETVAL, 0) == 2, 303)
			C.close(ready[0]); C.close(release[1])
			remove(id)
		}
	}
}

fn queued(mut t Totals) {
	unsafe {
		id := create()
		C.fflush(nil)
		pid := C.fork()
		if pid < 0 { fatal(10) }
		if pid == 0 {
			mut op := SemOp{ adjustment: -1 }
			outcome := invoke(0, id, &op, 1, nil)
			C._exit(if outcome.value == 0 { 0 } else { 1 })
		}
		for _ in 0 .. 5000 {
			if ctl(id, 0, C.GETNCNT, 0) == 1 { break }
			C.usleep(1000)
		}
		check(mut t, ctl(id, 0, C.GETNCNT, 0) == 1, 400)
		mut undo := SemOp{ adjustment: 1 flags: i16(C.SEM_UNDO) }
		expect(mut t, invoke(0, id, &undo, 1, nil), C.EOPNOTSUPP, 401)
		check(mut t, ctl(id, 0, C.GETVAL, 0) == 0 && ctl(id, 0, C.GETNCNT, 0) == 1, 402)
		mut grant := SemOp{ adjustment: 1 }
		expect(mut t, invoke(0, id, &grant, 1, nil), 0, 403)
		reap(pid, mut t)
		remove(id)
	}
}

fn suite(reference bool, mut t Totals) {
	common(mut t)
	exit_adjustment(reference, mut t)
	// An older kernel may silently execute undo operations. Stop before the
	// blocking refusal cases if the exit test already exposed that behavior.
	if !reference && t.failures != 0 { return }
	if !reference { refusals(mut t); queued(mut t) }
}

@[export: 'main']
fn fixture_main(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		C.alarm(120)
		mut t := Totals{}
		suite(reference, mut t)
		mut pipe := [2]i32{}
		if C.pipe(&pipe[0]) != 0 { fatal(11) }
		C.fflush(nil)
		pid := C.fork()
		if pid < 0 { fatal(12) }
		if pid == 0 {
			C.close(pipe[0])
			if C.setuid(1000) != 0 { fatal(13) }
			mut child := Totals{}
			suite(reference, mut child)
			if C.write(pipe[1], &child, sizeof(Totals)) != sizeof(Totals) { fatal(14) }
			C.fflush(nil)
			C._exit(0)
		}
		C.close(pipe[1])
		mut child := Totals{}
		if C.read(pipe[0], &child, sizeof(Totals)) != sizeof(Totals) { fatal(15) }
		t.checks += child.checks; t.failures += child.failures
		reap(pid, mut t)
		C.close(pipe[0])
		C.printf(c'LINUX SEMUNDO SUMMARY: checks=%d failures=%d\n', t.checks, t.failures)
		if t.failures != 0 { C.printf(c'LINUX SEMUNDO: FAIL\n'); C.fflush(nil); return 1 }
		C.alarm(0)
		if reference { C.printf(c'LINUX SEMUNDO REFERENCE: PASS\n') }
		else { C.printf(c'LINUX SEMUNDO: PASS\n') }
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
