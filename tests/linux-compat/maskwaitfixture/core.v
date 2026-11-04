// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module maskwaitfixture

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <sys/epoll.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <ucontext.h>
#include <unistd.h>

@[typedef]
struct C.sigset_t {}
@[typedef]
struct C.siginfo_t {}
@[typedef]
struct C.ucontext_t {
	uc_sigmask C.sigset_t
}
struct C.sigaction {
mut:
	sa_sigaction fn (i32, &C.siginfo_t, voidptr)
	sa_mask C.sigset_t
	sa_flags i32
}
struct Totals { mut: checks int failures int }
struct Observation {
mut:
	signal int
	mask u64
	saved u64
	query isize
}
struct State {
	signal int
	wait int
	mode int
mut:
	calls int
	observed [2]Observation
}
__global ( state &State )
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
fn C.getuid() u32
fn C.getgid() u32
fn C._exit(i32)
fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaddset(&C.sigset_t, i32) i32

fn bit(signal int) u64 { return u64(1) << u64(signal - 1) }
fn fatal(stage int) {
	C.printf(c'LINUX MASKWAIT FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut totals Totals, good bool, stage int) {
	totals.checks++
	if !good {
		totals.failures++
		unsafe { C.printf(c'LINUX MASKWAIT MISMATCH: signal=%d wait=%d mode=%d stage=%d\n', state.signal, state.wait, state.mode, stage) }
	}
}
fn mask() u64 {
	mut value := u64(0)
	if C.syscall(isize(C.SYS_rt_sigprocmask), 2, unsafe { nil }, &value, usize(8)) != 0 { fatal(1) }
	return value
}
fn setmask(value u64) isize {
	return C.syscall(isize(C.SYS_rt_sigprocmask), 2, &value, unsafe { nil }, usize(8))
}
fn send_signal(signal int) isize {
	return C.syscall(isize(C.SYS_tgkill), C.syscall(isize(C.SYS_getpid)), C.syscall(isize(C.SYS_gettid)), signal)
}
fn handler(signum i32, _info &C.siginfo_t, context voidptr) {
	unsafe {
		mut s := state
		index := s.calls
		s.calls++
		if index >= 2 { fatal(2) }
		mut value := u64(0)
		result := C.syscall(isize(C.SYS_rt_sigprocmask), 2, nil, &value, usize(8))
		uc := &C.ucontext_t(context)
		s.observed[index] = Observation{signal: signum, mask: value, saved: *&u64(&uc.uc_sigmask), query: result}
		// NODEFER must actually permit recursive delivery even when the saved
		// pre-wait mask blocked this signal. Record results outside the handler.
		if index == 0 && s.mode == 1 && send_signal(s.signal) != 0 { fatal(3) }
	}
}
fn wait_call(kind int, temporary &u64, epfd int, timeout &i64) isize {
	unsafe {
		match kind {
			0 { return C.syscall(isize(C.SYS_rt_sigsuspend), temporary, usize(8)) }
			1 { return C.syscall(isize(C.SYS_ppoll), nil, usize(0), timeout, temporary, usize(8)) }
			2 {
				pair := [u64(temporary), u64(8)]!
				// Bound the pselect control independently of the separate empty,
				// untimed select admission contract.
				deadline := [i64(10), i64(0)]!
				return C.syscall(isize(C.SYS_pselect6), 0, nil, nil, nil, if timeout == nil { &deadline[0] } else { timeout }, &pair[0])
			}
			3 {
				mut events := [4]u64{}
				return C.syscall(isize(C.SYS_epoll_pwait), epfd, &events[0], 1, if timeout == nil { -1 } else { 0 }, temporary, usize(8))
			}
			4 {
				mut events := [4]u64{}
				return C.syscall(isize(C.SYS_epoll_pwait2), epfd, &events[0], 1, timeout, temporary, usize(8))
			}
			else { return setmask(*temporary) }
		}
	}
}
fn suite(signal int, kind int, mode int) Totals {
	unsafe {
		C.alarm(15)
		mut s := State{signal: signal, wait: kind, mode: mode}
		state = &s
		mut totals := Totals{}
		initial := mask()
		original := bit(signal) | bit(C.SIGINT)
		temporary := bit(C.SIGWINCH) | bit(C.SIGPIPE)
		extra := bit(C.SIGTERM) | if mode == 3 { bit(signal) } else { u64(0) }
		mut action := C.sigaction{sa_sigaction: handler, sa_flags: C.SA_SIGINFO
			| if mode in [1, 3] { C.SA_NODEFER } else { 0 }
			| if mode == 2 { C.SA_RESTART } else { 0 }}
		if C.sigemptyset(&action.sa_mask) != 0 || C.sigaddset(&action.sa_mask, C.SIGTERM) != 0
			|| (mode == 3 && C.sigaddset(&action.sa_mask, signal) != 0)
			|| C.sigaction(signal, &action, nil) != 0 { fatal(4) }
		epfd := int(C.syscall(isize(C.SYS_epoll_create1), 0))
		if epfd < 0 || setmask(original) != 0 { fatal(5) }
		check(mut totals, send_signal(signal) == 0, 10)
		check(mut totals, s.calls == 0 && mask() == original, 11)
		mut pending := u64(0)
		check(mut totals, C.syscall(isize(C.SYS_rt_sigpending), &pending, usize(8)) == 0 && pending == bit(signal), 12)
		result := wait_call(kind, &temporary, epfd, nil)
		call_errno := *C.__errno_location()
		check(mut totals, if kind == 5 { result == 0 } else { result == -1 && call_errno == C.EINTR }, 13)
		expected := temporary | extra | if mode == 1 { u64(0) } else { bit(signal) }
		check(mut totals, s.calls == if mode == 1 { 2 } else { 1 }, 14)
		check(mut totals, s.observed[0].signal == signal && s.observed[0].query == 0, 15)
		check(mut totals, s.observed[0].mask == expected, 16)
		check(mut totals, s.observed[0].saved == if kind == 5 { temporary } else { original }, 17)
		if mode == 1 {
			check(mut totals, s.observed[1].signal == signal && s.observed[1].query == 0, 18)
			check(mut totals, s.observed[1].mask == expected, 19)
			check(mut totals, s.observed[1].saved == expected, 20)
		}
		check(mut totals, mask() == if kind == 5 { temporary } else { original }, 21)
		// Consume a recursion left blocked by a broken handler mask, so each
		// case reports its failures and subsequent controls can still run.
		zero := [i64(0), i64(0)]!
		for C.syscall(isize(C.SYS_rt_sigtimedwait), &original, nil, &zero[0], usize(8)) > 0 {}
		check(mut totals, setmask(original) == 0, 22)
		if kind in [1, 2, 3, 4] {
			before := s.calls
			check(mut totals, wait_call(kind, &temporary, epfd, &zero[0]) == 0, 23)
			check(mut totals, mask() == original && s.calls == before, 24)
		}
		check(mut totals, C.close(epfd) == 0 && setmask(initial) == 0, 25)
		return totals
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.alarm(180)
		mut total := Totals{}
		for ordinary in [false, true]! { for signal in [10, 12]! { for kind in 0 .. 6 { for mode in 0 .. 4 {
			mut fds := [2]i32{}
			if C.pipe(&fds[0]) != 0 { fatal(6) }
			C.fflush(nil)
			pid := C.fork()
			if pid < 0 { fatal(7) }
			if pid == 0 {
				C.close(fds[0])
				if ordinary && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(8) }
				t := suite(signal, kind, mode)
				C.printf(c'LINUX MASKWAIT CASE: uid=%u gid=%u signal=%d wait=%d mode=%d checks=%d failures=%d\n', C.getuid(), C.getgid(), signal, kind, mode, t.checks, t.failures)
				if C.write(fds[1], &t, sizeof(Totals)) != sizeof(Totals) { fatal(9) }
				C.fflush(nil); C._exit(0)
			}
			C.close(fds[1])
			mut t := Totals{}
			if C.read(fds[0], &t, sizeof(Totals)) != sizeof(Totals) { fatal(10) }
			mut status := i32(0)
			if C.waitpid(pid, &status, 0) != pid || status != 0 { fatal(11) }
			C.close(fds[0])
			total.checks += t.checks; total.failures += t.failures
		} } } }
		C.printf(c'LINUX MASKWAIT SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
		if total.failures == 0 { C.printf(c'LINUX MASKWAIT: PASS\n') } else { C.printf(c'LINUX MASKWAIT: FAIL\n') }
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
