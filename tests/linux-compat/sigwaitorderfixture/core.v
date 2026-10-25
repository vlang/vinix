// SPDX-License-Identifier: GPL-2.0-or-later
module sigwaitorderfixture

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct Totals { mut: checks i32 failures i32 }
struct Timeout { sec i64 nsec i64 }
fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.pipe(&i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getpid() i32
fn C.kill(i32, i32) i32
fn C._exit(i32)

fn fatal(stage int) {
	C.printf(c'LINUX SIGWAITORDER FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut t Totals, good bool, stage int, a int, b int, mode int) {
	t.checks++
	if !good {
		t.failures++
		if t.failures <= 30 { C.printf(c'LINUX SIGWAITORDER MISMATCH: stage=%d a=%d b=%d mode=%d\n', stage, a, b, mode) }
	}
}
fn bit(signal int) u64 { return u64(1) << u64(signal - 1) }
fn wait(wanted u64, pointer voidptr) isize {
	mut timeout := Timeout{}
	mut error_pointer := C.__errno_location()
	unsafe { *error_pointer = 0 }
	return C.syscall(isize(C.SYS_rt_sigtimedwait), &wanted, pointer, &timeout, usize(8))
}
fn pending() u64 {
	mut output := u64(0)
	if C.syscall(isize(C.SYS_rt_sigpending), &output, usize(8)) != 0 { fatal(1) }
	return output
}
fn send(signal int, to_thread bool) {
	result := if to_thread {
		C.syscall(isize(C.SYS_tgkill), isize(C.getpid()), C.syscall(isize(C.SYS_gettid)), isize(signal))
	} else { isize(C.kill(C.getpid(), signal)) }
	if result != 0 { fatal(2) }
}
fn synchronous(signal int) bool { return signal == 4 || signal == 5 || signal == 7 || signal == 8 || signal == 11 || signal == 31 }

// Linux considers the thread's queue before the process queue. Within either
// queue the six synchronous signal numbers take priority, then numeric order.
// Distinct ordered pairs also exercise reversed insertion order. Payload queue
// depth and asynchronous races are outside this single-threaded probe.
fn pair(mut t Totals, a int, b int, mode int, filter bool, mask u64) {
	unsafe {
		thread_a := mode in [0, 2]!
		thread_b := mode in [0, 3]!
		send(3, false) // blocked, unwanted bystander
		send(a, thread_a)
		send(b, thread_b)
		check(mut t, pending() == (bit(3) | bit(a) | bit(b)), 10, a, b, mode)
		first := if filter { a } else if thread_a != thread_b {
			if thread_a { a } else { b }
		} else if synchronous(a) != synchronous(b) {
			if synchronous(a) { a } else { b }
		} else { if a < b { a } else { b } }
		second := if first == a { b } else { a }
		wanted := if filter { bit(a) } else { bit(a) | bit(b) }
		mut output := [136]u8{init: 0xa5}
		pointer := if mode % 2 == 0 { voidptr(&output[3]) } else { nil }
		result := wait(wanted, pointer)
		check(mut t, result == first, 11, a, b, mode)
		if pointer != nil {
			mut copied := output[3] == u8(first) && output[4] == 0 && output[5] == 0 && output[6] == 0
			for index in [0, 1, 2, 131, 132, 133, 134, 135]! { if output[index] != 0xa5 { copied = false } }
			check(mut t, copied, 12, a, b, mode)
		}
		check(mut t, pending() == (bit(3) | bit(second)), 13, a, b, mode)
		check(mut t, wait(bit(second), nil) == second, 14, a, b, mode)
		check(mut t, pending() == bit(3), 15, a, b, mode)
		check(mut t, wait(bit(3), nil) == 3, 16, a, b, mode)
		mut current_mask := u64(0)
		check(mut t, C.syscall(isize(C.SYS_rt_sigprocmask), isize(C.SIG_BLOCK), nil, &current_mask, usize(8)) == 0 && current_mask == mask, 17, a, b, mode)
		check(mut t, pending() == 0, 18, a, b, mode)
		last := wait(wanted, nil)
		check(mut t, last == -1 && *C.__errno_location() == C.EAGAIN, 19, a, b, mode)
	}
}

fn suite(mut t Totals) {
	unsafe {
	signals := [1, 2, 4, 5, 6, 7, 8, 10, 11, 12, 15, 31, 35, 48, 63, 64]!
	mut mask := bit(3)
	for signal in signals { mask |= bit(signal) }
	if C.syscall(isize(C.SYS_rt_sigprocmask), isize(C.SIG_SETMASK), &mask, unsafe { nil }, usize(8)) != 0 { fatal(3) }
	for a in signals {
		for b in signals {
			if a == b { continue }
			for mode in 0 .. 4 { pair(mut t, a, b, mode, false, mask) }
			// A wanted subset must leave the excluded signal pending even if
			// its queue or synchronous number would otherwise have priority.
			for mode in [0, 3]! { pair(mut t, a, b, mode, true, mask) }
		}
		// Same signal independently pending in the two pools is consumed twice.
		for mode in [2, 3]! { pair(mut t, a, a, mode, false, mask) }
	}
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.alarm(120)
		mut total := Totals{}
		for unprivileged in [false, true]! {
			mut pipe := [2]i32{}
			if C.pipe(&pipe[0]) != 0 { fatal(10) }
			C.fflush(nil)
			pid := C.fork()
			if pid < 0 { fatal(11) }
			if pid == 0 {
				C.close(pipe[0])
				if unprivileged && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(12) }
				mut t := Totals{}
				suite(mut t)
				if C.write(pipe[1], &t, sizeof(Totals)) != sizeof(Totals) { fatal(13) }
				C.fflush(nil); C._exit(0)
			}
			C.close(pipe[1])
			mut t := Totals{}
			if C.read(pipe[0], &t, sizeof(Totals)) != sizeof(Totals) { fatal(14) }
			mut status := i32(0)
			if C.waitpid(pid, &status, 0) != pid || status != 0 { fatal(15) }
			C.close(pipe[0])
			total.checks += t.checks; total.failures += t.failures
		}
		C.printf(c'LINUX SIGWAITORDER SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
		if total.failures == 0 { C.printf(c'LINUX SIGWAITORDER: PASS\n') } else { C.printf(c'LINUX SIGWAITORDER: FAIL\n') }
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
