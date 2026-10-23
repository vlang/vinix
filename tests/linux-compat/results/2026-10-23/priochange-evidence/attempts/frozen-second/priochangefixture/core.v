// SPDX-License-Identifier: GPL-2.0-or-later
module priochangefixture

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
	code i32
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
	C.printf(c'LINUX PRIOCHANGE FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(90)
}
fn check(mut t Totals, good bool, stage i32) {
	t.checks++
	if !good {
		t.failures++
		if t.failures <= 16 { C.printf(c'LINUX PRIOCHANGE MISMATCH: stage=%d\n', stage) }
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
		if C.setpriority(C.PRIO_PROCESS, 0, wanted) != 0 || C.setresuid(uid, 41002, 0) != 0 { fatal(2) }
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
		mut code := i32(0)
		mut command := Command{}
		for {
			result := Reply{process: C.getpid(), first: first.tid, second: second.tid,
				code: code, failed: first.failed | second.failed}
			if C.write(reply, &result, sizeof(result)) != sizeof(result) { fatal(5) }
			if C.read(request, &command, sizeof(command)) != sizeof(command) { fatal(6) }
			code = 0
			if command.action == 1 && C.setpgid(0, command.value) != 0 { fatal(7) }
			if command.action in [2, 3, 6, 7] {
				which := if command.action == 2 { i32(C.PRIO_PGRP) } else { i32(C.PRIO_USER) }
				who := if command.action == 6 { u32(41001) } else if command.action == 7 { u32(41003) } else { u32(0) }
				location := C.__errno_location()
				*location = 0
				if C.setpriority(which, who, command.value) != 0 { code = *location }
			}
			if command.action == 5 && C.setresuid(41003, 41005, 0) != 0 { fatal(8) }
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
fn expect_set(mut t Totals, which u64, who u64, value u64, code i32, stage i32) {
	unsafe {
		location := C.__errno_location()
		*location = 0
		raw := C.syscall(C.SYS_setpriority, which, who, value)
		check(mut t, raw == if code == 0 { isize(0) } else { isize(-1) } && *location == code, stage)
		*location = 0
		libc := C.setpriority(i32(which), u32(who), i32(value))
		check(mut t, libc == if code == 0 { i32(0) } else { i32(-1) } && *location == code, stage + 1)
	}
}
fn expect_task(mut t Totals, tid i32, wanted i32) {
	unsafe {
		location := C.__errno_location()
		*location = 0
		check(mut t, C.syscall(C.SYS_getpriority, 0, tid) == 20 - wanted && *location == 0, 700)
		*location = 0
		check(mut t, C.getpriority(0, u32(tid)) == wanted && *location == 0, 701)
	}
}
fn targets(mut t Totals, a Peer, boot Reply, b Peer, c Peer, wanted i32) {
	for tid in [a.pid, boot.first, boot.second, b.pid]! { expect_task(mut t, tid, wanted) }
	expect_task(mut t, c.pid, -1)
}
fn variants(mut t Totals, which i32, who i32, value i32, code i32, stage i32) {
	unsafe {
		for high in [u64(0), 0x1234567800000000, 0xffffffff00000000]! {
			for upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! {
				for extra in [u64(0), 0x1234567800000000, 0xffffffff00000000]! {
					expect_set(mut t, high | u64(u32(which)), upper | u64(u32(who)), extra | u64(u32(value)), code, stage)
				}
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
		boot := receive(a)
		check(mut t, boot.process == a.pid && boot.first != a.pid && boot.second != a.pid
			&& boot.first != boot.second && boot.failed == 0, 100)
		b := start(1, a.pid)
		second := receive(b)
		check(mut t, second.process == b.pid && second.failed == 0, 101)
		c := start(2, 0)
		third := receive(c)
		check(mut t, third.process == c.pid && third.failed == 0, 102)
		for which := -32; which < 34; which++ {
			if which in [0, 1, 2] { continue }
			for who in [i32(-1), 0, 1, 2147483647, a.pid]! { variants(mut t, which, who, -21, C.EINVAL, 200) }
		}
		for which in [i32(0), 1, 2]! {
			variants(mut t, which, -1, 5, C.ESRCH, 300)
			variants(mut t, which, 2147483647, 5, C.ESRCH, 302)
		}
		// Select by real UID, despite all three processes sharing an effective UID.
		for which in [i32(1), 2]! {
			who := if which == 1 { a.pid } else { i32(41001) }
			for value in [i32(-2147483648), -21, -20, -1, 0, 18, 19, 20, 2147483647]! {
				wanted := if value < -20 { i32(-20) } else if value > 19 { i32(19) } else { value }
				for high in [u64(0), 0x1234567800000000, 0xffffffff00000000]! {
					for upper in [u64(0), 0x1234567800000000, 0xffffffff00000000]! {
						for extra in [u64(0), 0x1234567800000000, 0xffffffff00000000]! {
							expect_set(mut t, high | u64(u32(which)), upper | u64(u32(who)), extra | u64(u32(value)), 0, 400)
							targets(mut t, a, boot, b, c, wanted)
						}
					}
				}
			}
		}
		variants(mut t, 2, 41002, 10, C.ESRCH, 410)
		variants(mut t, 1, boot.first, 10, C.ESRCH, 412)
		expect_set(mut t, 1, u64(a.pid), 5, 0, 420)
		targets(mut t, a, boot, b, c, 5)
		for action in [i32(2), 3]! {
			wanted := if action == 2 { i32(8) } else { i32(9) }
			send(a, action, wanted)
			result := receive(a)
			check(mut t, result.code == 0 && result.failed == 0, 430)
			targets(mut t, a, boot, b, c, wanted)
		}
		send(c, 5, 0)
		check(mut t, receive(c).code == 0, 440)
		send(c, 1, a.pid)
		check(mut t, receive(c).code == 0, 441)
		// Group update must visit permitted tasks even when another member refuses.
		send(a, 2, 18)
		check(mut t, receive(a).code == C.EPERM, 450)
		targets(mut t, a, boot, b, c, 18)
		// Same owner, no CAP_SYS_NICE and RLIMIT_NICE=0: cannot lower nice.
		send(a, 6, 17)
		check(mut t, receive(a).code == C.EACCES, 460)
		targets(mut t, a, boot, b, c, 18)
		send(a, 7, 19)
		check(mut t, receive(a).code == C.EPERM, 470)
		targets(mut t, a, boot, b, c, 18)
		stop(b)
		stop(a)
		stop(c)
		variants(mut t, 1, a.pid, 0, C.ESRCH, 480)
		variants(mut t, 2, 41001, 0, C.ESRCH, 482)
		variants(mut t, 2, 41003, 0, C.ESRCH, 484)
		C.printf(c'LINUX PRIOCHANGE SUMMARY: checks=%d failures=%d\n', t.checks, t.failures)
		if t.failures != 0 { C.puts(c'LINUX PRIOCHANGE: FAIL'); C.fflush(nil); return 1 }
		C.puts(if reference { c'LINUX PRIOCHANGE REFERENCE: PASS' } else { c'LINUX PRIOCHANGE: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
