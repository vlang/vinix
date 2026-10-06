// SPDX-License-Identifier: BSD-2-Clause
// Independent native signal fixture translated from test.c:543-619.
@[translated]
@[has_globals]
module signalfixture

#include <signalfixture_v_contract.h>

struct C.vqs_volatile_signal {
mut:
	value i32
}

@[typedef]
struct C.sigset_t {}

struct C.sigaction {
mut:
	sa_handler fn (i32)
	sa_mask C.sigset_t
}

struct C.timespec {
mut:
	tv_sec i64
	tv_nsec i64
}

@[c_extern]
__global C.errno i32

__global qemu_signal_seen C.vqs_volatile_signal

fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fork() i32
fn C.getpid() i32
fn C.pause() i32
fn C.kill(i32, i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFSIGNALED(i32) bool
fn C.WTERMSIG(i32) i32
fn C.reap_ok(i32) i32
fn C._exit(i32)
fn C.memset(voidptr, i32, usize) voidptr
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.nanosleep(&C.timespec, &C.timespec) i32
fn C.vqs_busy_loop_handler(i32)

fn check(ok bool, line i32, expression &char) bool {
	if !ok {
		unsafe { C.printf(c'QEMU CORE FAIL line %d: %s (errno=%d)\n', line, expression, C.errno) }
	}
	return ok
}

@[export: 'test_default_terminating_signals']
pub fn default_terminating_signals() i32 {
	unsafe {
		mut child := C.fork()
		if !check(child >= 0, 547, c'child >= 0') { return 1 }
		if child == 0 {
			for { C.pause() }
		}
		if !check(C.kill(child, C.SIGTERM) == 0, 552, c'kill(child, SIGTERM) == 0') { return 1 }
		mut status := i32(-1)
		if !check(C.waitpid(child, &status, 0) == child, 554, c'waitpid(child, &status, 0) == child') { return 1 }
		if !check(C.WIFSIGNALED(status) && C.WTERMSIG(status) == C.SIGTERM, 555, c'WIFSIGNALED(status) && WTERMSIG(status) == SIGTERM') { return 1 }

		child = C.fork()
		if !check(child >= 0, 558, c'child >= 0') { return 1 }
		if child == 0 {
			for { C.pause() }
		}
		if !check(C.kill(child, C.SIGKILL) == 0, 563, c'kill(child, SIGKILL) == 0') { return 1 }
		status = -1
		if !check(C.waitpid(child, &status, 0) == child, 565, c'waitpid(child, &status, 0) == child') { return 1 }
		if !check(C.WIFSIGNALED(status) && C.WTERMSIG(status) == C.SIGKILL, 566, c'WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL') { return 1 }
		if !check(C.kill(C.getpid(), C.SIGWINCH) == 0, 569, c'kill(getpid(), SIGWINCH) == 0') { return 1 }
		C.puts(c'QEMU CORE PASS: default signal dispositions')
		return 0
	}
}

@[export: 'vqs_busy_loop_handler']
pub fn busy_loop_handler(signal i32) {
	_ = signal
	unsafe { qemu_signal_seen.value = 1 }
}

@[export: 'test_signals_reach_a_busy_loop']
pub fn signals_reach_a_busy_loop() i32 {
	unsafe {
		mut child := C.fork()
		if !check(child >= 0, 588, c'child >= 0') { return 1 }
		if child == 0 {
			mut action := C.sigaction{}
			C.memset(&action, 0, sizeof(action))
			action.sa_handler = C.vqs_busy_loop_handler
			C.sigemptyset(&action.sa_mask)
			if C.sigaction(C.SIGUSR1, &action, nil) != 0 { C._exit(2) }
			for qemu_signal_seen.value == 0 {}
			C._exit(0)
		}
		mut pause_for := C.timespec{tv_sec: 0, tv_nsec: 200000000}
		C.nanosleep(&pause_for, nil)
		if !check(C.kill(child, C.SIGUSR1) == 0, 602, c'kill(child, SIGUSR1) == 0') { return 1 }
		if !check(C.reap_ok(child) == 0, 603, c'reap_ok(child) == 0') { return 1 }

		child = C.fork()
		if !check(child >= 0, 606, c'child >= 0') { return 1 }
		if child == 0 { for {} }
		C.nanosleep(&pause_for, nil)
		if !check(C.kill(child, C.SIGKILL) == 0, 612, c'kill(child, SIGKILL) == 0') { return 1 }
		mut status := i32(-1)
		if !check(C.waitpid(child, &status, 0) == child, 614, c'waitpid(child, &status, 0) == child') { return 1 }
		if !check(C.WIFSIGNALED(status) && C.WTERMSIG(status) == C.SIGKILL, 615, c'WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL') { return 1 }
		C.puts(c'QEMU CORE PASS: signals reach a thread that makes no syscalls')
		return 0
	}
}
