// SPDX-License-Identifier: GPL-2.0-or-later
module semarrayfixture

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/sem.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[packed]
struct SemOp {
	number     u16
	adjustment i16
	flags      i16
}

struct Outcome {
	result isize
	code   i32
}

struct Worker {
	pid i32
	fd  i32
}

struct Totals {
mut:
	checks   i32
	failures i32
}

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.pipe2(&i32, i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.alarm(u32) u32
fn C.usleep(u32) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.strcmp(&char, &char) i32
fn C._exit(i32)
fn C.sysconf(i32) isize
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32

fn ctl(id i32, number i32, command i32, argument isize) isize {
	pointer := C.__errno_location()
	unsafe { *pointer = 0 }
	return C.syscall(isize(C.SYS_semctl), isize(id), isize(number), isize(command), argument)
}

fn fatal(stage i32) {
	C.printf(c'LINUX SEMARRAY FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(90)
}

fn check(mut totals Totals, good bool, stage i32) {
	totals.checks++
	if !good {
		totals.failures++
		C.printf(c'LINUX SEMARRAY MISMATCH: stage=%d\n', stage)
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

fn snapshot(id i32, values [4]u16, pids [4]i32, mut totals Totals, stage i32) {
	for number in 0 .. 4 {
		value := ctl(id, i32(number), C.GETVAL, 0)
		check(mut totals, value == unsafe { values[number] } && unsafe { *C.__errno_location() } == 0, stage + i32(number))
		pid := ctl(id, i32(number), C.GETPID, 0)
		check(mut totals, pid == unsafe { pids[number] } && unsafe { *C.__errno_location() } == 0, stage + 4 + i32(number))
	}
}

fn basic(parent i32, mut totals Totals) {
	unsafe {
		for count in [i32(1), 4, 32]! {
			id := create(count)
			mut buffer := [34]u16{}
			for index in 0 .. 34 { buffer[index] = 0xabcd }
			result(mut totals, ctl(id, -1, C.GETALL, isize(&buffer[1])), 0, 100 + count)
			check(mut totals, buffer[0] == 0xabcd && buffer[count + 1] == 0xabcd, 140 + count)
			for index in 0 .. count {
				check(mut totals, buffer[index + 1] == 0, 200 + index)
				check(mut totals, ctl(id, index, C.GETPID, 0) == 0, 240 + index)
			}
			// GETALL/SETALL ignore semnum, including negative and huge indices.
			for iteration in 0 .. 3 {
				mut input := [32]u16{}
				for index in 0 .. count { input[index] = u16((index + iteration) * 37) }
				input[count - 1] = if iteration == 0 { u16(32767) } else { u16(0) }
				number := if iteration == 0 {
					i32(-1)
				} else if iteration == 1 {
					i32(2147483647)
				} else {
					i32(-2147483647 - 1)
				}
				result(mut totals, ctl(id, number, C.SETALL, isize(&input[0])), 0, 300 + i32(iteration))
				for index in 0 .. count {
					check(mut totals, ctl(id, index, C.GETVAL, 0) == input[index], 340 + index)
					check(mut totals, ctl(id, index, C.GETPID, 0) == parent, 380 + index)
				}
				result(mut totals, ctl(id, number, C.GETALL, isize(&buffer[1])), 0, 420 + i32(iteration))
				mut equal := buffer[0] == 0xabcd && buffer[count + 1] == 0xabcd
				for index in 0 .. count { equal = equal && buffer[index + 1] == input[index] }
				check(mut totals, equal, 430 + i32(iteration))
			}
			remove(id)
		}
	}
}

fn faults(parent i32, mut totals Totals) {
	unsafe {
		id := create(4)
		wanted := [u16(3), 5, 7, 9]!
		pids := [parent, parent, parent, parent]!
		for index in 0 .. 4 { set_value(id, i32(index), wanted[index]) }
		for bad in [isize(0), -1]! {
			result(mut totals, ctl(id, 0, C.SETALL, bad), C.EFAULT, 500)
			snapshot(id, wanted, pids, mut totals, 501)
			result(mut totals, ctl(id, 0, C.GETALL, bad), C.EFAULT, 510)
		}
		for index in 0 .. 4 {
			mut values := [u16(1), 2, 4, 8]!
			values[index] = if index % 2 == 0 { u16(32768) } else { u16(65535) }
			result(mut totals, ctl(id, 0, C.SETALL, isize(&values[0])), C.ERANGE, 520 + i32(index))
			snapshot(id, wanted, pids, mut totals, 530)
		}
		page := C.sysconf(C._SC_PAGESIZE)
		if page < 4096 { fatal(4) }
		memory := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if memory == voidptr(-1) { fatal(5) }
		if C.mprotect(voidptr(isize(memory) + page), usize(page), C.PROT_NONE) != 0 { fatal(6) }
		// Exact length at the page boundary must not access an extra ushort.
		mut edge := &u16(isize(memory) + page - 8)
		for index in 0 .. 4 { edge[index] = wanted[index] }
		result(mut totals, ctl(id, 0, C.SETALL, isize(edge)), 0, 550)
		result(mut totals, ctl(id, 0, C.GETALL, isize(edge)), 0, 551)
		snapshot(id, wanted, pids, mut totals, 552)
		// A fault in the last member wins over an invalid first member.
		mut crossing := &u16(isize(memory) + page - 6)
		crossing[0] = 65535
		result(mut totals, ctl(id, 0, C.SETALL, isize(crossing)), C.EFAULT, 570)
		snapshot(id, wanted, pids, mut totals, 571)
		result(mut totals, ctl(id, 0, C.GETALL, isize(crossing)), C.EFAULT, 580)
		for index in 0 .. 4 { edge[index] = wanted[index] }
		if C.mprotect(memory, usize(page), C.PROT_READ) != 0 { fatal(7) }
		result(mut totals, ctl(id, 0, C.SETALL, isize(edge)), 0, 581)
		result(mut totals, ctl(id, 0, C.GETALL, isize(edge)), C.EFAULT, 582)
		snapshot(id, wanted, pids, mut totals, 583)
		if C.munmap(memory, usize(page * 2)) != 0 { fatal(8) }
		for command in [i32(C.GETALL), C.SETALL]! {
			result(mut totals, ctl(-1, -1, command, 0), C.EINVAL, 600)
		}
		remove(id)
		for command in [i32(C.GETALL), C.SETALL]! {
			result(mut totals, ctl(id, -1, command, 0), C.EINVAL, 601)
		}
	}
}

fn start(id i32, operations [3]SemOp, count i32, array bool) Worker {
	mut channel := [i32(-1), i32(-1)]!
	if C.pipe2(unsafe { &channel[0] }, 0) != 0 { fatal(9) }
	child := C.fork()
	if child < 0 { fatal(10) }
	if child == 0 {
		C.close(channel[0])
		C.alarm(30)
		ready := u8(0x5a)
		if C.write(channel[1], &ready, 1) != 1 { C._exit(91) }
		mut ops := [operations[0], operations[1], operations[2]]!
		values := [u16(0), 5, 7, 9]!
		pointer := C.__errno_location()
		unsafe { *pointer = 0 }
		value := if array {
			ctl(id, -1, C.SETALL, isize(unsafe { &values[0] }))
		} else {
			C.syscall(isize(C.SYS_semop), isize(id), unsafe { &ops[0] }, isize(count))
		}
		outcome := Outcome{ result: value, code: unsafe { *pointer } }
		if C.write(channel[1], &outcome, sizeof(Outcome)) != isize(sizeof(Outcome)) { C._exit(92) }
		C._exit(0)
	}
	if C.close(channel[1]) != 0 { fatal(11) }
	mut ready := u8(0)
	if C.read(channel[0], &ready, 1) != 1 || ready != 0x5a { fatal(12) }
	return Worker{ pid: child, fd: channel[0] }
}

fn finish(worker Worker, mut totals Totals, stage i32) {
	mut outcome := Outcome{}
	received := C.read(worker.fd, &outcome, sizeof(Outcome))
	if C.close(worker.fd) != 0 { fatal(13) }
	mut status := i32(-1)
	if C.waitpid(worker.pid, &status, 0) != worker.pid { fatal(14) }
	check(mut totals, received == isize(sizeof(Outcome)) && status == 0, stage)
	check(mut totals, outcome.result == 0 && outcome.code == 0, stage + 1)
}

fn await_waiter(id i32, number i32, command i32, mut totals Totals, stage i32) {
	mut ready := false
	for _ in 0 .. 2000 {
		if ctl(id, number, command, 0) == 1 {
			ready = true
			break
		}
		C.usleep(1000)
	}
	check(mut totals, ready, stage)
	if !ready { fatal(15) }
}

fn queued(parent i32, mut totals Totals) {
	unsafe {
		id := create(4)
		for index in 0 .. 4 { set_value(id, i32(index), [i32(0), 5, 7, 9]![index]) }
		child := start(id, [SemOp{}, SemOp{}, SemOp{}]!, 0, true)
		finish(child, mut totals, 700)
		// Same-value SETALL must still replace every recorded PID.
		snapshot(id, [u16(0), 5, 7, 9]!, [child.pid, child.pid, child.pid, child.pid]!, mut totals, 702)
		// This vector can run only after all SETALL values have been committed.
		decrement := start(id, [SemOp{ adjustment: -2 }, SemOp{ number: 2, adjustment: -11 }, SemOp{}]!, 2, false)
		zero := start(id, [SemOp{ number: 1 }, SemOp{}, SemOp{}]!, 1, false)
		await_waiter(id, 0, C.GETNCNT, mut totals, 720)
		await_waiter(id, 1, C.GETZCNT, mut totals, 721)
		values := [u16(2), 0, 11, 13]!
		result(mut totals, ctl(id, 0, C.SETALL, isize(&values[0])), 0, 722)
		// Let the original kernel finish too, so the baseline yields a full receipt.
		if ctl(id, 0, C.GETNCNT, 0) != 0 {
			set_value(id, 2, 11)
			set_value(id, 0, 2)
		}
		if ctl(id, 1, C.GETZCNT, 0) != 0 { set_value(id, 1, 0) }
		finish(decrement, mut totals, 723)
		finish(zero, mut totals, 725)
		snapshot(id, [u16(0), 0, 0, 13]!, [decrement.pid, zero.pid, decrement.pid, parent]!, mut totals, 727)
		// An invalid SETALL must neither mutate metadata nor wake a waiter.
		blocked := start(id, [SemOp{ adjustment: -1 }, SemOp{}, SemOp{}]!, 1, false)
		await_waiter(id, 0, C.GETNCNT, mut totals, 740)
		invalid := [u16(1), 2, 3, 65535]!
		result(mut totals, ctl(id, 0, C.SETALL, isize(&invalid[0])), C.ERANGE, 741)
		check(mut totals, ctl(id, 0, C.GETNCNT, 0) == 1, 742)
		snapshot(id, [u16(0), 0, 0, 13]!, [decrement.pid, zero.pid, decrement.pid, parent]!, mut totals, 743)
		set_value(id, 0, 1)
		finish(blocked, mut totals, 751)
		remove(id)
	}
}

@[export: 'main']
fn fixture_main(argc i32, argv &&char) i32 {
	reference := argc == 2 && unsafe { C.strcmp(argv[1], c'--reference') == 0 }
	C.alarm(60)
	mut totals := Totals{}
	parent := i32(C.syscall(isize(C.SYS_getpid)))
	basic(parent, mut totals)
	faults(parent, mut totals)
	queued(parent, mut totals)
	C.printf(c'LINUX SEMARRAY SUMMARY: checks=%d failures=%d\n', totals.checks, totals.failures)
	if totals.failures != 0 {
		C.puts(c'LINUX SEMARRAY: FAIL')
		C.fflush(unsafe { nil })
		return 1
	}
	C.puts(if reference { c'LINUX SEMARRAY REFERENCE: PASS' } else { c'LINUX SEMARRAY: PASS' })
	C.fflush(unsafe { nil })
	C.alarm(0)
	for { C.pause() }
	return 0
}
