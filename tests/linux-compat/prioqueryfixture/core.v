// SPDX-License-Identifier: GPL-2.0-or-later
module prioqueryfixture

#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}

struct Totals {
mut:
	checks i32
	failures i32
}

struct Command {
	action i32
	value i32
}

struct Reply {
mut:
	process i32
	first i32
	second i32
	group i32
	user i32
	self i32
	failed i32
}

struct Worker {
mut:
	tid i32
	wanted i32
	actual i32
	stop i32
	failed i32
}

struct Peer {
	pid i32
	request i32
	reply i32
}

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.getpriority(i32, u32) i32
fn C.setpriority(i32, u32, i32) i32
fn C.setresuid(u32, u32, u32) i32
fn C.setpgid(i32, i32) i32
fn C.getpid() i32
fn C.pipe(&i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.alarm(u32) u32
fn C.pause() i32
fn C.sched_yield() i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.strcmp(&char, &char) i32

fn fatal(stage i32) {
	C.printf(c'LINUX PRIOQUERY FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(90)
}

fn check(mut totals Totals, good bool, stage i32) {
	totals.checks++
	if !good {
		totals.failures++
		if totals.failures <= 16 { C.printf(c'LINUX PRIOQUERY MISMATCH: stage=%d\n', stage) }
	}
}

fn worker(argument voidptr) voidptr {
	unsafe {
		mut state := &Worker(argument)
		state.tid = i32(C.syscall(C.SYS_gettid))
		for {
			if C.__atomic_load_n(&state.stop, 2) != 0 { return nil }
			wanted := C.__atomic_load_n(&state.wanted, 2)
			if wanted != C.__atomic_load_n(&state.actual, 2) {
				if C.setpriority(C.PRIO_PROCESS, 0, wanted) != 0 { state.failed = 1 }
				C.__atomic_store_n(&state.actual, wanted, 3)
			}
			C.sched_yield()
		}
	}
	return unsafe { nil }
}

fn child(request i32, reply i32, role i32) {
	unsafe {
		mut boot := i32(0)
		if C.read(request, &boot, sizeof(boot)) != sizeof(boot) || boot != 1 { fatal(1) }
		wanted := if role == 0 { i32(5) } else if role == 1 { i32(7) } else { i32(-1) }
		uid := if role < 2 { u32(41001) } else { u32(41003) }
		euid := if role == 0 { u32(41002) } else if role == 1 { u32(41004) } else { u32(41001) }
		if C.setpriority(C.PRIO_PROCESS, 0, wanted) != 0 || C.setresuid(uid, euid, 0) != 0 { fatal(2) }
		mut first := Worker{wanted: 11, actual: -99}
		mut second := Worker{wanted: 17, actual: -99}
		mut one := C.pthread_t{}
		mut two := C.pthread_t{}
		if role == 0 {
			if C.pthread_create(&one, nil, worker, &first) != 0
				|| C.pthread_create(&two, nil, worker, &second) != 0 { fatal(3) }
			for C.__atomic_load_n(&first.actual, 2) != 11 || C.__atomic_load_n(&second.actual, 2) != 17 { C.sched_yield() }
			if C.setpriority(C.PRIO_PROCESS, 0, 19) != 0 { fatal(4) }
		}
		mut command := Command{}
		for {
			mut result := Reply{process: C.getpid(), first: first.tid, second: second.tid,
				failed: first.failed | second.failed}
			location := C.__errno_location()
			*location = 0
			result.self = C.getpriority(C.PRIO_PROCESS, 0)
			if *location != 0 { result.failed = 1 }
			*location = 0
			result.group = C.getpriority(C.PRIO_PGRP, 0)
			if *location != 0 { result.failed = 1 }
			*location = 0
			result.user = C.getpriority(C.PRIO_USER, 0)
			if *location != 0 { result.failed = 1 }
			if C.write(reply, &result, sizeof(result)) != sizeof(result) { fatal(5) }
			if C.read(request, &command, sizeof(command)) != sizeof(command) { fatal(6) }
			if command.action == 1 && C.setpgid(0, 0) != 0 { fatal(7) }
			if command.action == 2 && C.setpriority(C.PRIO_PROCESS, 0, command.value) != 0 { fatal(8) }
			if command.action == 3 {
				C.__atomic_store_n(&first.wanted, command.value, 3)
				for C.__atomic_load_n(&first.actual, 2) != command.value { C.sched_yield() }
			}
			if command.action == 4 {
				if role == 0 {
					C.__atomic_store_n(&first.stop, 1, 3)
					C.__atomic_store_n(&second.stop, 1, 3)
					if C.pthread_join(one, nil) != 0 || C.pthread_join(two, nil) != 0 { fatal(9) }
				}
				C._exit(0)
			}
		}
	}
}

fn start(role i32, group i32) Peer {
	unsafe {
		mut request := [2]i32{}
		mut reply := [2]i32{}
		if C.pipe(&request[0]) != 0 || C.pipe(&reply[0]) != 0 { fatal(10) }
		pid := C.fork()
		if pid < 0 { fatal(11) }
		if pid == 0 {
			C.close(request[1]); C.close(reply[0])
			child(request[0], reply[1], role)
			C._exit(91)
		}
		C.close(request[0]); C.close(reply[1])
		if C.setpgid(pid, if group == 0 { pid } else { group }) != 0 { fatal(12) }
		boot := i32(1)
		if C.write(request[1], &boot, sizeof(boot)) != sizeof(boot) { fatal(13) }
		return Peer{pid, request[1], reply[0]}
	}
}

fn receive(peer Peer) Reply {
	mut reply := Reply{}
	if C.read(peer.reply, unsafe { &reply }, sizeof(reply)) != sizeof(reply) { fatal(14) }
	return reply
}

fn send(peer Peer, action i32, value i32) {
	command := Command{action, value}
	if C.write(peer.request, unsafe { &command }, sizeof(command)) != sizeof(command) { fatal(15) }
}

fn expect(mut t Totals, which u64, who u64, wanted i32, code i32, stage i32) {
	unsafe {
		location := C.__errno_location()
		*location = 0
		raw := C.syscall(C.SYS_getpriority, which, who)
		check(mut t, raw == if code == 0 { isize(20 - wanted) } else { isize(-1) }
			&& *location == code, stage)
		*location = 0
		libc := C.getpriority(i32(which), u32(who))
		check(mut t, libc == if code == 0 { wanted } else { i32(-1) } && *location == code, stage + 1)
	}
}

fn variants(mut t Totals, which i32, who i32, wanted i32, code i32, stage i32) {
	unsafe {
	for high in [u64(0), 0x1234567800000000, 0xffffffff00000000]! {
		for upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! {
			expect(mut t, high | u64(u32(which)), upper | u64(u32(who)), wanted, code, stage)
		}
	}
	}
}

fn stop(peer Peer) {
	send(peer, 4, 0)
	mut status := i32(-1)
	if C.waitpid(peer.pid, unsafe { &status }, 0) != peer.pid || status != 0 { fatal(16) }
	C.close(peer.request); C.close(peer.reply)
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.alarm(90)
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		mut t := Totals{}
		a := start(0, 0)
		initial := receive(a)
		check(mut t, initial.process == a.pid && initial.first != a.pid && initial.second != a.pid
			&& initial.first != initial.second && initial.self == 19 && initial.group == 11
			&& initial.user == 11 && initial.failed == 0, 100)
		b := start(1, a.pid)
		second := receive(b)
		check(mut t, second.self == 7 && second.group == 7 && second.user == 7 && second.failed == 0, 101)
		c := start(2, 0)
		third := receive(c)
		check(mut t, third.self == -1 && third.group == -1 && third.user == -1 && third.failed == 0, 102)
		for which := -32; which < 34; which++ {
			if which in [0, 1, 2] { continue }
			for who in [i32(-1), 0, 1, 2147483647, a.pid]! { variants(mut t, which, who, 0, C.EINVAL, 200) }
		}
		for which in [i32(0), 1, 2]! {
			variants(mut t, which, -1, 0, C.ESRCH, 300)
			variants(mut t, which, 2147483647, 0, C.ESRCH, 302)
		}
		variants(mut t, 0, a.pid, 19, 0, 310)
		variants(mut t, 0, initial.first, 11, 0, 312)
		variants(mut t, 0, initial.second, 17, 0, 314)
		variants(mut t, 1, a.pid, 7, 0, 320)
		variants(mut t, 1, initial.first, 0, C.ESRCH, 322)
		variants(mut t, 1, b.pid, 0, C.ESRCH, 324)
		variants(mut t, 2, 41001, 7, 0, 330)
		variants(mut t, 2, 41002, 0, C.ESRCH, 332)
		variants(mut t, 2, 41003, -1, 0, 334)
		variants(mut t, 2, 41004, 0, C.ESRCH, 336)
		send(b, 1, 0)
		moved := receive(b)
		check(mut t, moved.group == 7 && moved.user == 7 && moved.failed == 0, 400)
		variants(mut t, 1, a.pid, 11, 0, 410)
		variants(mut t, 1, b.pid, 7, 0, 412)
		variants(mut t, 2, 41001, 7, 0, 414)
		send(a, 3, 15)
		raised := receive(a)
		check(mut t, raised.group == 15 && raised.self == 19 && raised.user == 7 && raised.failed == 0, 420)
		variants(mut t, 0, initial.first, 15, 0, 422)
		variants(mut t, 0, initial.second, 17, 0, 424)
		variants(mut t, 1, a.pid, 15, 0, 426)
		send(b, 2, 18)
		last := receive(b)
		check(mut t, last.self == 18 && last.group == 18 && last.user == 15 && last.failed == 0, 430)
		variants(mut t, 2, 41001, 15, 0, 432)
		send(c, 2, 19)
		other := receive(c)
		check(mut t, other.self == 19 && other.group == 19 && other.user == 19 && other.failed == 0, 440)
		variants(mut t, 2, 41003, 19, 0, 442)
		stop(b)
		variants(mut t, 1, b.pid, 0, C.ESRCH, 450)
		variants(mut t, 2, 41001, 15, 0, 452)
		stop(a)
		variants(mut t, 1, a.pid, 0, C.ESRCH, 454)
		variants(mut t, 2, 41001, 0, C.ESRCH, 456)
		stop(c)
		variants(mut t, 2, 41003, 0, C.ESRCH, 458)
		C.printf(c'LINUX PRIOQUERY SUMMARY: checks=%d failures=%d\n', t.checks, t.failures)
		if t.failures != 0 { C.puts(c'LINUX PRIOQUERY: FAIL'); C.fflush(nil); return 1 }
		C.puts(if reference { c'LINUX PRIOQUERY REFERENCE: PASS' } else { c'LINUX PRIOQUERY: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
