// SPDX-License-Identifier: GPL-2.0-or-later
// ioprio_get(2)/ioprio_set(2): validation, 16-bit storage, argument words and
// error order; inheritance by fork, threads and exec; process-group and user
// aggregation in fresh groups and uids; unprivileged limits; kcmp(KCMP_IO).
// The same ELF runs as Vinix's init and, given --reference, under Linux.
module iopriofixture

#include <alloca.h>
#include <errno.h>
#include <grp.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.pthread_t {}

struct C.sched_param {
mut:
	sched_priority i32
}

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.getpid() i32
fn C.pipe(&i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.setpriority(i32, u32, i32) i32
fn C.setpgid(i32, i32) i32
fn C.kill(i32, i32) i32
fn C.execv(&char, &&char) i32
fn C.strcmp(&char, &char) i32
fn C.alloca(usize) voidptr
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32

const who_process = i64(1)
const who_pgrp = i64(2)
const who_user = i64(3)
const be = i64(2 << 13)
const rt = i64(1 << 13)
const idle = i64(3 << 13)
const missing = i64(0x3ffffff0)

struct State {
mut:
	checks   int
	failures int
}

struct Result {
	value isize
	err   int
}

fn get(which i64, who i64) Result {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		value := C.syscall(isize(C.SYS_ioprio_get), which, who)
		return Result{value, if value < 0 { *errno_ptr } else { 0 }}
	}
}

fn set(which i64, who i64, value i64) Result {
	unsafe {
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		result := C.syscall(isize(C.SYS_ioprio_set), which, who, value)
		return Result{result, if result < 0 { *errno_ptr } else { 0 }}
	}
}

fn check(mut s State, label &char, ok bool, got Result) {
	s.checks++
	if !ok {
		s.failures++
		C.printf(c'LINUX IOPRIO FAIL: %s value=%ld errno=%d\n', label, got.value, got.err)
	}
}

// A successful call returns `want`; a failing one fails with errno `err`.
fn expect(mut s State, label &char, got Result, want i64, err int) {
	ok := if err == 0 { got.value == isize(want) && got.err == 0 } else { got.value == -1 && got.err == err }
	check(mut s, label, ok, got)
}

fn kcmp_io(a i64, b i64) isize {
	return C.syscall(isize(C.SYS_kcmp), a, b, 5, 0, 0)
}

fn wait_byte(fd i32) {
	mut value := u8(0)
	unsafe { C.read(fd, &value, 1) }
}

// A member of group `group` (0: a new one it leads) that applies nice, then a
// policy (-1: none) and a priority (-1: none) before it reports ready.
fn member(group i32, nice i32, policy i32, value i64) i32 {
	unsafe {
		mut ready := [2]i32{}
		C.pipe(&ready[0])
		child := C.fork()
		if child == 0 {
			C.setpgid(0, group)
			if nice != 0 { C.setpriority(0, 0, nice) }
			if policy >= 0 {
				mut param := C.sched_param{}
				param.sched_priority = if policy == 1 { 10 } else { 0 }
				C.syscall(isize(C.SYS_sched_setscheduler), 0, policy, &param)
			}
			if value >= 0 { C.syscall(isize(C.SYS_ioprio_set), 1, 0, value) }
			mut byte := u8(1)
			C.write(ready[1], &byte, 1)
			for { C.pause() }
		}
		C.setpgid(child, if group == 0 { child } else { group })
		wait_byte(ready[0])
		C.close(ready[0])
		C.close(ready[1])
		return child
	}
}

fn reap(first i32, second i32) {
	unsafe {
		for p in [first, second]! {
			if p > 0 {
				C.kill(p, 9)
				C.waitpid(p, nil, 0)
			}
		}
	}
}

// The aggregate of a fresh group of one or two members.
fn group_case(mut s State, label &char, first_nice i32, first_value i64, second_nice i32, second_value i64, two bool, want i64) {
	a := member(0, first_nice, -1, first_value)
	b := if two { member(a, second_nice, -1, second_value) } else { i32(0) }
	expect(mut s, label, get(who_pgrp, a), want, 0)
	reap(a, b)
}

fn validation(mut s State) {
	// Each value set, and what is stored after it (-1: refused with EINVAL).
	values := [i64(0), 1, 7, 8, rt, rt | 7, rt | 8, rt | 0x1ff8, be, be | 7, be | 0x18, be | 0x1fff,
		idle, idle | 7, idle | 8, i64(4 << 13), i64(7 << 13), i64(0x10000), i64(0x10000) | be | 3, -1,
		i64(0x7fffffff), i64(0x1_0000_0000) | be | 5]!
	stored := [i64(0), -1, -1, 8, rt, rt | 7, rt | 8, rt | 0x1ff8, be, be | 7, be | 0x18, be | 0x1fff,
		idle, idle | 7, idle | 8, -1, -1, 0, be | 3, -1, -1, be | 5]!
	mut current := i64(0)
	for index in 0 .. values.len {
		result := set(who_process, 0, unsafe { values[index] })
		expect(mut s, c'validate set', result, 0, if unsafe { stored[index] } < 0 { C.EINVAL } else { 0 })
		if unsafe { stored[index] } >= 0 { current = unsafe { stored[index] } }
		expect(mut s, c'validate stored', get(who_process, 0), current, 0)
	}
	expect(mut s, c'which word', set(i64(0x1_0000_0000) | who_process, 0, be | 6), 0, 0)
	expect(mut s, c'which word get', get(i64(0x1_0000_0000) | who_process, 0), be | 6, 0)
	expect(mut s, c'who word', get(who_process, i64(0x7_0000_0000)), be | 6, 0)
	unsafe {
	for which in [i64(0), 4, 9, -1]! {
		expect(mut s, c'bad which set', set(which, 0, be | 4), 0, C.EINVAL)
		expect(mut s, c'bad which get', get(which, 0), 0, C.EINVAL)
	}
	}
	expect(mut s, c'missing set', set(who_process, missing, be | 4), 0, C.ESRCH)
	expect(mut s, c'missing get', get(who_process, missing), 0, C.ESRCH)
	// The value is checked before which and who.
	expect(mut s, c'value before which', set(9, 0, -1), 0, C.EINVAL)
	expect(mut s, c'value before who', set(who_process, missing, -1), 0, C.EINVAL)
	expect(mut s, c'missing group', get(who_pgrp, missing), 0, C.ESRCH)
	expect(mut s, c'missing group set', set(who_pgrp, missing, be), 0, C.ESRCH)
	expect(mut s, c'missing user', get(who_user, 54321), 0, C.ESRCH)
	expect(mut s, c'missing user set', set(who_user, 54321, be), 0, C.ESRCH)
}

fn thread_main(arg voidptr) voidptr {
	unsafe {
		*&i64(arg) = i64(C.syscall(isize(C.SYS_gettid)))
		for { C.pause() }
	}
	return unsafe { nil }
}

fn inheritance(mut s State, pid i64) {
	unsafe {
		expect(mut s, c'default', get(who_process, 0), 0, 0)
		expect(mut s, c'default by pid', get(who_process, pid), 0, 0)
		plain := member(0, 0, -1, -1)
		expect(mut s, c'fork without context', get(who_process, plain), 0, 0)
		check(mut s, c'kcmp io without contexts', kcmp_io(pid, plain) == 0, Result{kcmp_io(pid, plain), 0})
		reap(plain, 0)
		set(who_process, 0, be | 3)
		valid := member(0, 0, -1, -1)
		expect(mut s, c'fork inherits valid class', get(who_process, valid), be | 3, 0)
		io := kcmp_io(pid, valid)
		check(mut s, c'kcmp io own context', io == 1 || io == 2, Result{io, 0})
		reap(valid, 0)
		set(who_process, 0, 0)
		expect(mut s, c'none set', get(who_process, 0), 0, 0)
		classless := member(0, 0, -1, -1)
		expect(mut s, c'fork skips class none', get(who_process, classless), 0, 0)
		io_none := kcmp_io(pid, classless)
		check(mut s, c'kcmp io context against none', io_none == 1 || io_none == 2, Result{io_none, 0})
		reap(classless, 0)
		// A thread gets its own copy; setting it leaves the creator's alone.
		set(who_process, 0, be | 2)
		mut tid := i64(0)
		handle := &C.pthread_t(C.alloca(usize(sizeof(C.pthread_t))))
		C.pthread_create(handle, nil, thread_main, &tid)
		for katomic_load(&tid) == 0 { C.sched_yield() }
		expect(mut s, c'thread inherits', get(who_process, tid), be | 2, 0)
		io_thread := kcmp_io(pid, tid)
		check(mut s, c'kcmp io thread', io_thread == 1 || io_thread == 2, Result{io_thread, 0})
		expect(mut s, c'set thread', set(who_process, tid, be | 6), 0, 0)
		expect(mut s, c'thread own', get(who_process, tid), be | 6, 0)
		expect(mut s, c'creator unchanged', get(who_process, 0), be | 2, 0)
		// Exec keeps the context.
		child := C.fork()
		if child == 0 {
			C.syscall(isize(C.SYS_ioprio_set), 1, 0, be | 5)
			mut argv := &&char(C.alloca(usize(3 * sizeof(voidptr))))
			argv[0] = &char(c'ioprio-exec')
			argv[1] = &char(c'--ioprio-exec')
			argv[2] = nil
			C.execv(c'/proc/self/exe', argv)
			C._exit(3)
		}
		mut status := i32(0)
		C.waitpid(child, &status, 0)
		check(mut s, c'exec keeps context', status == 0, Result{isize(status), 0})
		// Class NONE keeps the context but is not inherited: later children start
		// without one.
		expect(mut s, c'reset to none', set(who_process, 0, 0), 0, 0)
	}
}

fn katomic_load(value &i64) i64 {
	return C.__atomic_load_n(value, C.__ATOMIC_ACQUIRE)
}

fn C.__atomic_load_n(&i64, i32) i64
fn C.sched_yield() i32

fn aggregation(mut s State) {
	group_case(mut s, c'group no context', 0, -1, 0, -1, false, be | 4)
	nices := [i32(10), -20, -1, 15, 4, 5]!
	levels := [i64(6), 0, 3, 7, 4, 5]!
	for index in 0 .. nices.len {
		group_case(mut s, c'group nice', unsafe { nices[index] }, -1, 0, -1, false, be | unsafe { levels[index] })
	}
	group_case(mut s, c'group none context nice', 10, 0, 0, -1, false, be | 6)
	group_case(mut s, c'group none hint', 0, 0x18, 0, -1, false, be | 4)
	group_case(mut s, c'pair none and set', 0, -1, 0, be | 3, true, be | 3)
	group_case(mut s, c'pair set and none', 0, be | 3, 0, -1, true, be | 3)
	group_case(mut s, c'pair levels', 0, be | 6, 0, be | 5, true, be | 5)
	group_case(mut s, c'pair idle', 0, idle, 0, be | 7, true, be | 7)
	group_case(mut s, c'pair rt', 0, rt | 7, 0, be, true, rt | 7)
	group_case(mut s, c'pair nice contexts', 10, 0, -5, 0, true, be | 3)
	group_case(mut s, c'pair hints', 0, be | 0x18, 0, be | 3, true, be | 3)
	// Without a class of its own a task's follows its CPU policy.
	fifo := member(0, 0, 1, -1)
	expect(mut s, c'group fifo', get(who_pgrp, fifo), rt | 4, 0)
	reap(fifo, 0)
	idle_task := member(0, 0, 5, -1)
	expect(mut s, c'group sched idle', get(who_pgrp, idle_task), idle | 4, 0)
	reap(idle_task, 0)
	fifo_be := member(0, 0, 1, be | 5)
	expect(mut s, c'group fifo with class', get(who_pgrp, fifo_be), be | 5, 0)
	reap(fifo_be, 0)
	// Setting a group reaches every member.
	a := member(0, 0, -1, -1)
	b := member(a, 0, -1, be | 6)
	expect(mut s, c'group set', set(who_pgrp, a, be | 1), 0, 0)
	expect(mut s, c'group set first', get(who_process, a), be | 1, 0)
	expect(mut s, c'group set second', get(who_process, b), be | 1, 0)
	reap(a, b)
	// Group 0 is the caller's.
	unsafe {
		child := C.fork()
		if child == 0 {
			C.setpgid(0, 0)
			mut local := State{}
			expect(mut local, c'own group set', set(who_pgrp, 0, be | 2), 0, 0)
			expect(mut local, c'own group get', get(who_pgrp, 0), be | 2, 0)
			expect(mut local, c'own group member', get(who_process, 0), be | 2, 0)
			C.fflush(nil)
			C._exit(local.failures)
		}
		mut status := i32(0)
		C.waitpid(child, &status, 0)
		check(mut s, c'own group', status == 0, Result{isize(status), 0})
	}
}

// Members owned by `uid`, made by root.
fn user_member(uid u32, value i64) i32 {
	unsafe {
		mut ready := [2]i32{}
		C.pipe(&ready[0])
		child := C.fork()
		if child == 0 {
			C.setgroups(0, nil)
			C.setgid(uid)
			C.setuid(uid)
			if value >= 0 { C.syscall(isize(C.SYS_ioprio_set), 1, 0, value) }
			mut byte := u8(1)
			C.write(ready[1], &byte, 1)
			for { C.pause() }
		}
		wait_byte(ready[0])
		C.close(ready[0])
		C.close(ready[1])
		return child
	}
}

fn users(mut s State, pid i64) {
	a := user_member(1001, be | 6)
	b := user_member(1001, -1)
	expect(mut s, c'user best', get(who_user, 1001), be | 4, 0)
	expect(mut s, c'user set', set(who_user, 1001, be | 1), 0, 0)
	expect(mut s, c'user set first', get(who_process, a), be | 1, 0)
	expect(mut s, c'user set second', get(who_process, b), be | 1, 0)
	reap(a, b)
	group := member(0, 0, -1, be | 3)
	unsafe {
		child := C.fork()
		if child == 0 {
			C.setgroups(0, nil)
			C.setgid(1000)
			C.setuid(1000)
			mut local := State{}
			expect(mut local, c'read root task', get(who_process, group), be | 3, 0)
			expect(mut local, c'unprivileged rt', set(who_process, 0, rt | 4), 0, C.EPERM)
			expect(mut local, c'unprivileged idle', set(who_process, 0, idle), 0, 0)
			expect(mut local, c'unprivileged be7', set(who_process, 0, be | 7), 0, 0)
			expect(mut local, c'unprivileged be0', set(who_process, 0, be), 0, 0)
			expect(mut local, c'unprivileged root task', set(who_process, pid, be | 4), 0, C.EPERM)
			expect(mut local, c'unprivileged cap first', set(who_process, missing, rt | 4), 0, C.EPERM)
			expect(mut local, c'unprivileged cap before which', set(9, 0, rt | 4), 0, C.EPERM)
			expect(mut local, c'unprivileged invalid', set(9, 0, -1), 0, C.EINVAL)
			expect(mut local, c'unprivileged own uid', set(who_user, 1000, be | 5), 0, 0)
			expect(mut local, c'unprivileged own users', get(who_user, 0), be | 5, 0)
			// Linux sets uid 0's tasks for who 0, though get reads the caller's.
			expect(mut local, c'unprivileged user zero', set(who_user, 0, be | 4), 0, C.EPERM)
			expect(mut local, c'unprivileged root group', set(who_pgrp, group, be | 4), 0, C.EPERM)
			C.printf(c'LINUX IOPRIO CHILD: checks=%d failures=%d\n', local.checks, local.failures)
			C.fflush(nil)
			C._exit(if local.failures == 0 { 0 } else { 1 })
		}
		mut status := i32(0)
		C.waitpid(child, &status, 0)
		check(mut s, c'unprivileged child', status == 0, Result{isize(status), 0})
	}
	reap(group, 0)
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		if argc > 1 && C.strcmp(argv[1], c'--ioprio-exec') == 0 {
			C._exit(if get(who_process, 0).value == isize(be | 5) { 0 } else { 1 })
		}
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		mut s := State{}
		pid := i64(C.getpid())
		inheritance(mut s, pid)
		child := C.fork()
		if child == 0 {
			mut local := State{}
			validation(mut local)
			C.printf(c'LINUX IOPRIO VALIDATION: checks=%d failures=%d\n', local.checks, local.failures)
			C.fflush(nil)
			C._exit(if local.failures == 0 { 0 } else { 1 })
		}
		mut status := i32(0)
		C.waitpid(child, &status, 0)
		check(mut s, c'validation child', status == 0, Result{isize(status), 0})
		aggregation(mut s)
		users(mut s, pid)
		C.printf(c'LINUX IOPRIO SUMMARY: checks=%d failures=%d\n', s.checks, s.failures)
		if s.failures == 0 {
			C.puts(if reference { c'LINUX IOPRIO REFERENCE: PASS' } else { c'LINUX IOPRIO: PASS' })
		}
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
