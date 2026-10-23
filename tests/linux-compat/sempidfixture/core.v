// SPDX-License-Identifier: GPL-2.0-or-later
module sempidfixture

#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/sem.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

@[packed]
struct SemOp {
	number u16
	adjustment i16
	flags i16
}
struct C.timespec { tv_sec isize tv_nsec isize }
@[typedef]
struct C.pthread_t {}
struct Outcome { result isize code i32 }
struct Worker { pid i32 fd i32 }
struct ThreadState {
	id i32
mut:
	tid isize
	result isize
	code i32
}
struct Totals { mut: checks i32 failures i32 }

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.pipe2(&i32, i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.kill(i32, i32) i32
fn C.signal(i32, fn(i32)) voidptr
fn C.alarm(u32) u32
fn C.usleep(u32) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.strcmp(&char, &char) i32
fn C._exit(i32)
fn C.pthread_create(&C.pthread_t, voidptr, fn(voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32

fn clear_errno() { pointer := C.__errno_location(); unsafe { *pointer = 0 } }

fn ctl(id i32, number i32, command i32, argument isize) isize {
	clear_errno()
	return C.syscall(isize(C.SYS_semctl), isize(id), isize(number), isize(command), argument)
}

fn fatal(stage i32) {
	C.printf(c'LINUX SEMPID FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(90)
}

fn check(mut totals Totals, good bool, stage i32) {
	totals.checks++
	if !good {
		totals.failures++
		C.printf(c'LINUX SEMPID MISMATCH: stage=%d\n', stage)
	}
}

fn result(mut totals Totals, actual isize, code i32, stage i32) {
	err := unsafe { *C.__errno_location() }
	check(mut totals, actual == if code == 0 { isize(0) } else { isize(-1) } && err == code, stage)
}

fn create(count i32) i32 {
	id := i32(C.syscall(isize(C.SYS_semget), isize(C.IPC_PRIVATE), isize(count), isize(0o600)))
	if id < 0 { fatal(1) }
	return id
}

fn set_value(id i32, number i32, value i32) {
	if ctl(id, number, C.SETVAL, isize(value)) != 0 { fatal(2) }
}

fn remove(id i32) { if ctl(id, 0, C.IPC_RMID, 0) != 0 { fatal(3) } }

fn snapshot(id i32, wanted_values [4]i32, wanted_pids [4]i32, mut totals Totals, stage i32) {
	for number in 0 .. 4 {
		value := ctl(id, i32(number), C.GETVAL, 0)
		check(mut totals, value == unsafe { wanted_values[number] } && unsafe { *C.__errno_location() } == 0,
			stage + i32(number))
		pid := ctl(id, i32(number), C.GETPID, 0)
		check(mut totals, pid == unsafe { wanted_pids[number] } && unsafe { *C.__errno_location() } == 0,
			stage + 4 + i32(number))
	}
}

fn one(number u16, adjustment i16) [3]SemOp {
	return [SemOp{ number: number, adjustment: adjustment }, SemOp{}, SemOp{}]!
}

fn signal_handler(_ i32) {}

fn start(id i32, operations [3]SemOp, count i32, timeout_ms i32) Worker {
	mut channel := [i32(-1), i32(-1)]!
	if C.pipe2(unsafe { &channel[0] }, 0) != 0 { fatal(4) }
	child := C.fork()
	if child < 0 { fatal(5) }
	if child == 0 {
		C.close(channel[0])
		if C.signal(C.SIGUSR1, signal_handler) == voidptr(-1) { C._exit(91) }
		C.alarm(30)
		ready := u8(0x5a)
		if C.write(channel[1], &ready, 1) != 1 { C._exit(92) }
		mut ops := [operations[0], operations[1], operations[2]]!
		mut duration := C.timespec{ tv_sec: isize(timeout_ms / 1000), tv_nsec: isize(timeout_ms % 1000) * 1000000 }
		clear_errno()
		value := if timeout_ms < 0 {
			C.syscall(isize(C.SYS_semop), isize(id), unsafe { &ops[0] }, isize(count))
		} else {
			C.syscall(isize(C.SYS_semtimedop), isize(id), unsafe { &ops[0] }, isize(count), &duration)
		}
		outcome := Outcome{ result: value, code: unsafe { *C.__errno_location() } }
		if C.write(channel[1], &outcome, sizeof(Outcome)) != isize(sizeof(Outcome)) { C._exit(93) }
		C._exit(0)
	}
	if C.close(channel[1]) != 0 { fatal(6) }
	mut ready := u8(0)
	if C.read(channel[0], &ready, 1) != 1 || ready != 0x5a { fatal(7) }
	return Worker{ pid: child, fd: channel[0] }
}

fn finish(worker Worker, code i32, mut totals Totals, stage i32) {
	mut outcome := Outcome{}
	received := C.read(worker.fd, &outcome, sizeof(Outcome))
	if C.close(worker.fd) != 0 { fatal(8) }
	mut status := i32(-1)
	if C.waitpid(worker.pid, &status, 0) != worker.pid { fatal(9) }
	check(mut totals, received == isize(sizeof(Outcome)) && status == 0, stage)
	check(mut totals, outcome.result == if code == 0 { isize(0) } else { isize(-1) } && outcome.code == code, stage + 1)
}

fn await_waiter(id i32, number i32, command i32, mut totals Totals, stage i32) {
	mut ready := false
	for _ in 0 .. 2000 {
		if ctl(id, number, command, 0) == 1 { ready = true; break }
		C.usleep(1000)
	}
	check(mut totals, ready, stage)
	if !ready { fatal(10) }
}

fn immediate(parent i32, mut totals Totals) {
	id := create(4)
	snapshot(id, [i32(0), 0, 0, 0]!, [i32(0), 0, 0, 0]!, mut totals, 100)
	set_value(id, 1, 7)
	snapshot(id, [i32(0), 7, 0, 0]!, [i32(0), parent, 0, 0]!, mut totals, 110)
	a := start(id, one(0, 1), 1, -1)
	finish(a, 0, mut totals, 120)
	snapshot(id, [i32(1), 7, 0, 0]!, [a.pid, parent, 0, 0]!, mut totals, 122)
	// A zero operation records its caller even though no value changes.
	mut zero := SemOp{ number: 2 }
	clear_errno()
	result(mut totals, C.syscall(isize(C.SYS_semop), isize(id), &zero, isize(1)), 0, 130)
	snapshot(id, [i32(1), 7, 0, 0]!, [a.pid, parent, parent, 0]!, mut totals, 131)
	// A duplicate index and a net-zero change still record the child PID.
	ops := [SemOp{ adjustment: 1 }, SemOp{ adjustment: -1 }, SemOp{ number: 3 }]!
	b := start(id, ops, 3, -1)
	finish(b, 0, mut totals, 140)
	snapshot(id, [i32(1), 7, 0, 0]!, [b.pid, parent, parent, b.pid]!, mut totals, 142)
	set_value(id, 3, 0)
	snapshot(id, [i32(1), 7, 0, 0]!, [b.pid, parent, parent, parent]!, mut totals, 150)
	remove(id)
}

fn refusals(parent i32, mut totals Totals) {
	id := create(4)
	set_value(id, 1, 32767)
	a := start(id, one(0, 1), 1, -1)
	finish(a, 0, mut totals, 200)
	wanted_values := [i32(1), 32767, 0, 0]!
	wanted_pids := [a.pid, parent, i32(0), 0]!
	for kind in 0 .. 5 {
		mut ops := [SemOp{ adjustment: -1 }, SemOp{}, SemOp{}]!
		mut zero := C.timespec{}
		ops[1] = match kind {
			0 { SemOp{ number: 2, adjustment: -1, flags: i16(C.IPC_NOWAIT) } }
			1 { SemOp{ number: 1, adjustment: 1 } }
			2 { SemOp{ number: 4, adjustment: 1 } }
			else { SemOp{ number: 2, adjustment: -1 } }
		}
		clear_errno()
		value := if kind == 3 {
			C.syscall(isize(C.SYS_semop), isize(id), voidptr(1), isize(2))
		} else if kind == 4 {
			C.syscall(isize(C.SYS_semtimedop), isize(id), unsafe { &ops[0] }, isize(2), &zero)
		} else {
			C.syscall(isize(C.SYS_semop), isize(id), unsafe { &ops[0] }, isize(2))
		}
		code := match kind { 1 { i32(C.ERANGE) } 2 { i32(C.EFBIG) } 3 { i32(C.EFAULT) } else { i32(C.EAGAIN) } }
		result(mut totals, value, code, 210 + i32(kind) * 10)
		snapshot(id, wanted_values, wanted_pids, mut totals, 211 + i32(kind) * 10)
	}
	result(mut totals, ctl(id, 0, C.SETVAL, -1), C.ERANGE, 270)
	snapshot(id, wanted_values, wanted_pids, mut totals, 271)
	result(mut totals, ctl(id, 4, C.SETVAL, 1), C.EINVAL, 280)
	snapshot(id, wanted_values, wanted_pids, mut totals, 281)
	remove(id)
}

fn queued(parent i32, mut totals Totals) {
	id := create(4)
	set_value(id, 1, 5)
	ops := [SemOp{ adjustment: -1 }, SemOp{ number: 3, adjustment: 1 }, SemOp{ number: 2 }]!
	a := start(id, ops, 3, -1)
	await_waiter(id, 0, C.GETNCNT, mut totals, 300)
	snapshot(id, [i32(0), 5, 0, 0]!, [i32(0), parent, 0, 0]!, mut totals, 301)
	set_value(id, 0, 1)
	finish(a, 0, mut totals, 310)
	snapshot(id, [i32(0), 5, 0, 1]!, [a.pid, parent, a.pid, a.pid]!, mut totals, 312)
	zero_ops := [SemOp{ number: 3 }, SemOp{ number: 1, adjustment: 1 }, SemOp{}]!
	b := start(id, zero_ops, 2, -1)
	await_waiter(id, 3, C.GETZCNT, mut totals, 320)
	snapshot(id, [i32(0), 5, 0, 1]!, [a.pid, parent, a.pid, a.pid]!, mut totals, 321)
	set_value(id, 3, 0)
	finish(b, 0, mut totals, 330)
	snapshot(id, [i32(0), 6, 0, 0]!, [a.pid, b.pid, a.pid, b.pid]!, mut totals, 332)
	// Timeout and interruption discard the entire tentative prefix.
	failed := [SemOp{ number: 1, adjustment: 1 }, SemOp{ number: 2, adjustment: -1 }, SemOp{}]!
	timed := start(id, failed, 2, 1000)
	await_waiter(id, 2, C.GETNCNT, mut totals, 340)
	snapshot(id, [i32(0), 6, 0, 0]!, [a.pid, b.pid, a.pid, b.pid]!, mut totals, 341)
	finish(timed, C.EAGAIN, mut totals, 350)
	snapshot(id, [i32(0), 6, 0, 0]!, [a.pid, b.pid, a.pid, b.pid]!, mut totals, 352)
	interrupted := start(id, failed, 2, -1)
	await_waiter(id, 2, C.GETNCNT, mut totals, 360)
	if C.kill(interrupted.pid, C.SIGUSR1) != 0 { fatal(11) }
	finish(interrupted, C.EINTR, mut totals, 361)
	snapshot(id, [i32(0), 6, 0, 0]!, [a.pid, b.pid, a.pid, b.pid]!, mut totals, 363)
	remove(id)
}

fn thread_operation(argument voidptr) voidptr {
	unsafe {
		mut state := &ThreadState(argument)
		state.tid = C.syscall(isize(C.SYS_gettid))
		mut op := SemOp{ number: 1, adjustment: 1 }
		clear_errno()
		state.result = C.syscall(isize(C.SYS_semop), isize(state.id), &op, isize(1))
		state.code = *C.__errno_location()
		return nil
	}
}

fn thread_and_boundary(parent i32, mut totals Totals) {
	id := create(4)
	mut worker_thread := C.pthread_t{}
	mut state := ThreadState{ id: id }
	if C.pthread_create(&worker_thread, unsafe { nil }, thread_operation, &state) != 0 { fatal(12) }
	if C.pthread_join(worker_thread, unsafe { nil }) != 0 { fatal(13) }
	check(mut totals, state.tid > 0 && state.tid != parent && state.result == 0 && state.code == 0, 400)
	snapshot(id, [i32(0), 1, 0, 0]!, [i32(0), parent, 0, 0]!, mut totals, 401)
	remove(id)
	large := create(32)
	for number in 0 .. 32 {
		pid := ctl(large, i32(number), C.GETPID, 0)
		check(mut totals, pid == 0 && unsafe { *C.__errno_location() } == 0, 420 + i32(number))
	}
	a := start(large, one(31, 1), 1, -1)
	finish(a, 0, mut totals, 460)
	for number in 0 .. 32 {
		pid := ctl(large, i32(number), C.GETPID, 0)
		check(mut totals, pid == if number == 31 { isize(a.pid) } else { isize(0) }
			&& unsafe { *C.__errno_location() } == 0, 462 + i32(number))
	}
	remove(large)
}

@[export: 'main']
pub fn entry(argc i32, argv &&char) i32 {
	reference := argc == 2 && unsafe { C.strcmp(argv[1], c'--reference') == 0 }
	C.alarm(60)
	parent := i32(C.syscall(isize(C.SYS_getpid)))
	mut totals := Totals{}
	immediate(parent, mut totals)
	refusals(parent, mut totals)
	queued(parent, mut totals)
	thread_and_boundary(parent, mut totals)
	C.alarm(0)
	C.printf(c'LINUX SEMPID SUMMARY: checks=%d failures=%d\n', totals.checks, totals.failures)
	C.puts(if totals.failures != 0 { c'LINUX SEMPID: FAIL' } else if reference {
		c'LINUX SEMPID REFERENCE: PASS'
	} else { c'LINUX SEMPID: PASS' })
	C.fflush(unsafe { nil })
	if totals.failures != 0 { return 1 }
	for { C.pause() }
	return 0
}
