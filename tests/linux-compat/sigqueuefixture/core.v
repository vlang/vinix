// SPDX-License-Identifier: GPL-2.0-or-later
// Senders in siginfo: si_code/si_pid/si_uid for kill, tgkill and other
// processes and users, through sigtimedwait, signalfd and an SA_SIGINFO
// handler; rt_sigqueueinfo, rt_tgsigqueueinfo and pidfd_send_signal payloads
// and errors; no silent loss of a second real-time signal; the first sender
// of a merged standard signal.
// The same ELF runs as Vinix's init and, given --reference, under Linux.
module sigqueuefixture

#include <alloca.h>
#include <errno.h>
#include <grp.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/signalfd.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

struct C.pthread_t {}

@[typedef]
struct C.siginfo_t {}

struct C.timespec {
mut:
	tv_sec  i64
	tv_nsec i64
}

struct C.sigaction {
mut:
	sa_sigaction voidptr
	sa_flags     i32
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
fn C.dup2(i32, i32) i32
fn C.alloca(usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.strcmp(&char, &char) i32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.kill(i32, i32) i32
fn C.sigemptyset(voidptr) i32
fn C.sigaddset(voidptr, i32) i32
fn C.sigprocmask(i32, voidptr, voidptr) i32
fn C.pthread_sigmask(i32, voidptr, voidptr) i32
fn C.sigtimedwait(voidptr, &C.siginfo_t, &C.timespec) i32
fn C.sigaction(i32, &C.sigaction, voidptr) i32
fn C.signalfd(i32, voidptr, i32) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32

const usr1 = 10
const usr2 = 12
const rt1 = 40
const rt2 = 41
const si_user = 0
const si_queue = -1
const si_tkill = -6
const handler_fd = 50

struct State {
mut:
	checks   int
	failures int
}

struct Result {
	value isize
	err   int
}

// The fields a check compares: si_signo, si_code, si_pid, si_uid, si_value.
struct Info {
mut:
	signo int
	code  int
	pid   int
	uid   u32
	value u64
}

fn decode(raw &u8) Info {
	unsafe {
		return Info{
			signo: *&i32(raw)
			code:  *&i32(u64(raw) + 8)
			pid:   *&i32(u64(raw) + 16)
			uid:   *&u32(u64(raw) + 20)
			value: *&u64(u64(raw) + 24)
		}
	}
}

fn check(mut s State, label &char, ok bool, got Result) {
	s.checks++
	if !ok {
		s.failures++
		C.printf(c'LINUX SIGQUEUE FAIL: %s value=%ld errno=%d\n', label, got.value, got.err)
	}
}

fn result(value isize) Result {
	return Result{value, if value < 0 { unsafe { *C.__errno_location() } } else { 0 }}
}

fn fails(mut s State, label &char, got Result, err int) {
	check(mut s, label, got.value == -1 && got.err == err, got)
}

fn expect_info(mut s State, label &char, got Info, signo int, code int, pid int, uid u32, value u64, with_value bool) {
	ok := got.signo == signo && got.code == code && got.pid == pid && got.uid == uid
		&& (!with_value || got.value == value)
	if !ok {
		C.printf(c'LINUX SIGQUEUE INFO: %s signo=%d code=%d pid=%d uid=%u value=0x%lx\n', label,
			got.signo, got.code, got.pid, got.uid, got.value)
	}
	check(mut s, label, ok, Result{0, 0})
}

// A siginfo_t a caller hands to the queueing calls.
fn build(raw &u8, signo int, code int, pid int, uid u32, value u64) {
	unsafe {
		C.memset(raw, 0, 128)
		*&i32(raw) = i32(signo)
		*&i32(u64(raw) + 8) = i32(code)
		*&i32(u64(raw) + 16) = i32(pid)
		*&u32(u64(raw) + 20) = uid
		*&u64(u64(raw) + 24) = value
	}
}

fn queue(pid i64, signal i64, raw voidptr) Result {
	errno_ptr := C.__errno_location()
	unsafe { *errno_ptr = 0 }
	return result(C.syscall(isize(C.SYS_rt_sigqueueinfo), pid, signal, raw))
}

fn tgqueue(tgid i64, tid i64, signal i64, raw voidptr) Result {
	errno_ptr := C.__errno_location()
	unsafe { *errno_ptr = 0 }
	return result(C.syscall(isize(C.SYS_rt_tgsigqueueinfo), tgid, tid, signal, raw))
}

// Wait up to two seconds for `signal`, which the caller blocks.
fn take(signal int, raw &u8) int {
	unsafe {
		set := C.alloca(128)
		C.memset(set, 0, 128)
		C.sigaddset(set, signal)
		mut limit := C.timespec{
			tv_sec: 2
		}
		C.memset(raw, 0, 128)
		return C.sigtimedwait(set, &C.siginfo_t(raw), &limit)
	}
}

// Whether nothing of `signal` is left pending.
fn drained(signal int) bool {
	unsafe {
		set := C.alloca(128)
		C.memset(set, 0, 128)
		C.sigaddset(set, signal)
		mut limit := C.timespec{}
		return C.sigtimedwait(set, nil, &limit) == -1 && *C.__errno_location() == C.EAGAIN
	}
}

fn block(signal int) {
	unsafe {
		set := C.alloca(128)
		C.memset(set, 0, 128)
		C.sigaddset(set, signal)
		C.sigprocmask(C.SIG_BLOCK, set, nil)
	}
}

fn handler(signal i32, info &C.siginfo_t, context voidptr) {
	C.write(handler_fd, voidptr(info), 128)
}

struct Waiter {
mut:
	ready [2]i32
	tid   i64
	info  [16]u64
	got   int
}

fn waiter_main(arg voidptr) voidptr {
	unsafe {
		mut waiter := &Waiter(arg)
		waiter.tid = i64(C.syscall(isize(C.SYS_gettid)))
		mut byte := u8(1)
		C.write(waiter.ready[1], &byte, 1)
		waiter.got = take(rt2, &u8(&waiter.info[0]))
	}
	return unsafe { nil }
}

fn senders(mut s State, pid int) {
	unsafe {
		raw := &u8(C.alloca(128))
		C.kill(pid, usr1)
		expect_info(mut s, c'kill self', if take(usr1, raw) == usr1 { decode(raw) } else { Info{} },
			usr1, si_user, pid, 0, 0, false)
		C.syscall(isize(C.SYS_tgkill), pid, C.syscall(isize(C.SYS_gettid)), usr1)
		expect_info(mut s, c'tgkill self', if take(usr1, raw) == usr1 { decode(raw) } else { Info{} },
			usr1, si_tkill, pid, 0, 0, false)
		mut child := C.fork()
		if child == 0 {
			C.kill(pid, usr1)
			C._exit(0)
		}
		C.waitpid(child, nil, 0)
		expect_info(mut s, c'kill from child', if take(usr1, raw) == usr1 { decode(raw) } else { Info{} },
			usr1, si_user, child, 0, 0, false)
		child = C.fork()
		if child == 0 {
			build(raw, rt1, si_queue, C.getpid(), 0, 0x1234)
			C._exit(if queue(pid, rt1, raw).value == 0 { 0 } else { 1 })
		}
		mut status := i32(0)
		C.waitpid(child, &status, 0)
		check(mut s, c'child queued', status == 0, Result{isize(status), 0})
		expect_info(mut s, c'queue from child', if take(rt1, raw) == rt1 { decode(raw) } else { Info{} },
			rt1, si_queue, child, 0, 0x1234, true)
		// The caller's own fields are delivered as given.
		build(raw, rt1, -60, 4242, 77, u64(0xdeadbeefcafe))
		check(mut s, c'queue own fields', queue(pid, rt1, raw).value == 0, Result{0, 0})
		expect_info(mut s, c'own fields', if take(rt1, raw) == rt1 { decode(raw) } else { Info{} }, rt1,
			-60, 4242, 77, u64(0xdeadbeefcafe), true)
		// Itself, a process may use a kernel's code.
		build(raw, rt1, 3, 9, 8, 7)
		check(mut s, c'queue self kernel code', queue(pid, rt1, raw).value == 0, Result{0, 0})
		expect_info(mut s, c'self kernel code', if take(rt1, raw) == rt1 { decode(raw) } else { Info{} },
			rt1, 3, 9, 8, 7, true)
	}
}

// Between two UID 1000 processes, the receiver sees the sender's uid.
fn users(mut s State) {
	unsafe {
		mut channel := [2]i32{}
		C.pipe(&channel[0])
		receiver := C.fork()
		if receiver == 0 {
			C.setgroups(0, nil)
			C.setgid(1000)
			C.setuid(1000)
			block(usr1)
			mut byte := u8(1)
			C.write(channel[1], &byte, 1)
			raw := &u8(C.alloca(128))
			got := take(usr1, raw)
			C.write(channel[1], raw, 128)
			C._exit(if got == usr1 { 0 } else { 1 })
		}
		mut byte := u8(0)
		C.read(channel[0], &byte, 1)
		sender := C.fork()
		if sender == 0 {
			C.setgroups(0, nil)
			C.setgid(1000)
			C.setuid(1000)
			C._exit(if C.kill(receiver, usr1) == 0 { 0 } else { 1 })
		}
		C.waitpid(sender, nil, 0)
		received := &u8(C.alloca(128))
		C.read(channel[0], received, 128)
		C.waitpid(receiver, nil, 0)
		expect_info(mut s, c'other user', decode(received), usr1, si_user, sender, 1000, 0, false)
		C.close(channel[0])
		C.close(channel[1])
	}
}

fn readers(mut s State, pid int) {
	unsafe {
		raw := &u8(C.alloca(128))
		set := C.alloca(128)
		C.memset(set, 0, 128)
		C.sigaddset(set, usr2)
		C.sigaddset(set, rt2)
		C.sigprocmask(C.SIG_BLOCK, set, nil)
		fd := C.signalfd(-1, set, 0)
		C.kill(pid, usr2)
		C.memset(raw, 0, 128)
		C.read(fd, raw, 128)
		check(mut s, c'signalfd kill', *&u32(raw) == usr2 && *&i32(u64(raw) + 8) == si_user
			&& *&u32(u64(raw) + 12) == u32(pid) && *&u32(u64(raw) + 16) == 0, Result{0, 0})
		build(raw, rt2, si_queue, pid, 0, 99)
		queue(pid, rt2, raw)
		C.memset(raw, 0, 128)
		C.read(fd, raw, 128)
		check(mut s, c'signalfd queue', *&u32(raw) == rt2 && *&i32(u64(raw) + 8) == si_queue
			&& *&u32(u64(raw) + 12) == u32(pid) && *&i32(u64(raw) + 44) == 99
			&& *&u64(u64(raw) + 48) == 99, Result{0, 0})
		C.close(fd)
		// A thread named by rt_tgsigqueueinfo receives the payload itself.
		mut waiter := &Waiter(C.alloca(usize(sizeof(Waiter))))
		*waiter = Waiter{}
		C.pipe(&waiter.ready[0])
		handle := &C.pthread_t(C.alloca(usize(sizeof(C.pthread_t))))
		C.pthread_create(handle, nil, waiter_main, waiter)
		mut byte := u8(0)
		C.read(waiter.ready[0], &byte, 1)
		build(raw, rt2, si_queue, pid, 0, 7)
		check(mut s, c'thread queued', tgqueue(pid, waiter.tid, rt2, raw).value == 0, Result{0, 0})
		C.pthread_join(*handle, nil)
		expect_info(mut s, c'thread payload', if waiter.got == rt2 {
			decode(&u8(&waiter.info[0]))
		} else {
			Info{}
		}, rt2, si_queue, pid, 0, 7, true)
		// An SA_SIGINFO handler sees the sender too.
		mut ends := [2]i32{}
		C.pipe(&ends[0])
		C.dup2(ends[1], handler_fd)
		mut action := C.sigaction{}
		action.sa_sigaction = voidptr(handler)
		action.sa_flags = C.SA_SIGINFO
		C.sigaction(usr2, &action, nil)
		child := C.fork()
		if child == 0 {
			C.kill(pid, usr2)
			C._exit(0)
		}
		C.waitpid(child, nil, 0)
		C.sigprocmask(C.SIG_UNBLOCK, set, nil)
		C.memset(raw, 0, 128)
		got := C.read(ends[0], raw, 128)
		expect_info(mut s, c'handler', if got == 128 { decode(raw) } else { Info{} }, usr2, si_user,
			child, 0, 0, false)
		C.sigprocmask(C.SIG_BLOCK, set, nil)
		C.close(ends[0])
		C.close(ends[1])
		C.close(handler_fd)
	}
}

fn errors(mut s State, pid int) {
	unsafe {
		raw := &u8(C.alloca(128))
		build(raw, rt1, si_queue, pid, 0, 1)
		fails(mut s, c'queue fault', queue(pid, rt1, voidptr(1)), C.EFAULT)
		child := C.fork()
		if child == 0 { for { C.pause() } }
		for code in [si_user, 1, si_tkill]! {
			build(raw, rt1, code, pid, 0, 1)
			fails(mut s, c'forged code', queue(child, rt1, raw), C.EPERM)
		}
		build(raw, rt1, si_queue, pid, 0, 1)
		for bad in [0, -1, 0x3ffffff0]! {
			fails(mut s, c'missing process', queue(bad, rt1, raw), C.ESRCH)
		}
		// The process is looked up before the signal is checked.
		fails(mut s, c'missing before signal', queue(0x3ffffff0, 65, raw), C.ESRCH)
		fails(mut s, c'bad signal', queue(pid, 65, raw), C.EINVAL)
		check(mut s, c'existence probe', queue(child, 0, raw).value == 0, Result{0, 0})
		// rt_tgsigqueueinfo
		fails(mut s, c'thread fault', tgqueue(pid, pid, rt1, voidptr(1)), C.EFAULT)
		fails(mut s, c'thread id zero', tgqueue(pid, 0, rt1, raw), C.EINVAL)
		fails(mut s, c'group id zero', tgqueue(0, pid, rt1, raw), C.EINVAL)
		build(raw, rt1, si_tkill, pid, 0, 1)
		fails(mut s, c'thread forged', tgqueue(child, child, rt1, raw), C.EPERM)
		build(raw, rt1, si_queue, pid, 0, 1)
		fails(mut s, c'thread wrong group', tgqueue(child, pid, rt1, raw), C.ESRCH)
		fails(mut s, c'thread bad signal', tgqueue(pid, pid, 65, raw), C.EINVAL)
		// pidfd_send_signal with a siginfo.
		own := i32(C.syscall(isize(C.SYS_pidfd_open), pid, 0))
		other := i32(C.syscall(isize(C.SYS_pidfd_open), child, 0))
		build(raw, rt2, si_queue, pid, 0, 1)
		errno_ptr := C.__errno_location()
		*errno_ptr = 0
		fails(mut s, c'pidfd signo', result(C.syscall(isize(C.SYS_pidfd_send_signal), own, rt1, raw, 0)),
			C.EINVAL)
		build(raw, rt1, si_user, pid, 0, 1)
		fails(mut s, c'pidfd forged', result(C.syscall(isize(C.SYS_pidfd_send_signal), other, rt1, raw, 0)),
			C.EPERM)
		build(raw, rt1, si_queue, pid, 0, 31)
		check(mut s, c'pidfd queue', C.syscall(isize(C.SYS_pidfd_send_signal), own, rt1, raw, 0) == 0,
			Result{0, 0})
		expect_info(mut s, c'pidfd payload', if take(rt1, raw) == rt1 { decode(raw) } else { Info{} },
			rt1, si_queue, pid, 0, 31, true)
		C.close(own)
		C.close(other)
		// An unprivileged process may not queue for root.
		sender := C.fork()
		if sender == 0 {
			C.setgroups(0, nil)
			C.setgid(1000)
			C.setuid(1000)
			build(raw, rt1, si_queue, C.getpid(), 1000, 1)
			r := queue(pid, rt1, raw)
			C._exit(if r.value == -1 && r.err == C.EPERM { 0 } else { 1 })
		}
		mut status := i32(0)
		C.waitpid(sender, &status, 0)
		check(mut s, c'unprivileged', status == 0, Result{isize(status), 0})
		C.kill(child, 9)
		C.waitpid(child, nil, 0)
	}
}

// A second real-time signal is either delivered after the first or refused;
// a standard signal merges and keeps its first sender.
fn merging(mut s State, pid int) {
	unsafe {
		raw := &u8(C.alloca(128))
		build(raw, rt1, si_queue, pid, 0, 1)
		first := queue(pid, rt1, raw)
		build(raw, rt1, si_queue, pid, 0, 2)
		second := queue(pid, rt1, raw)
		check(mut s, c'first real-time', first.value == 0, first)
		check(mut s, c'second real-time', second.value == 0 || (second.value == -1 && second.err == C.EAGAIN),
			second)
		got := if take(rt1, raw) == rt1 { decode(raw) } else { Info{} }
		check(mut s, c'first delivered first', got.value == 1, Result{isize(got.value), 0})
		if second.value == 0 {
			again := if take(rt1, raw) == rt1 { decode(raw) } else { Info{} }
			check(mut s, c'second delivered', again.value == 2, Result{isize(again.value), 0})
		}
		check(mut s, c'real-time drained', drained(rt1), Result{0, 0})
		build(raw, usr1, si_queue, pid, 0, 5)
		check(mut s, c'standard first', queue(pid, usr1, raw).value == 0, Result{0, 0})
		build(raw, usr1, si_queue, pid, 0, 6)
		check(mut s, c'standard merged', queue(pid, usr1, raw).value == 0, Result{0, 0})
		kept := if take(usr1, raw) == usr1 { decode(raw) } else { Info{} }
		check(mut s, c'standard keeps first', kept.value == 5, Result{isize(kept.value), 0})
		check(mut s, c'standard drained', drained(usr1), Result{0, 0})
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		mut s := State{}
		pid := C.getpid()
		for signal in [usr1, usr2, rt1, rt2]! { block(signal) }
		senders(mut s, pid)
		users(mut s)
		readers(mut s, pid)
		errors(mut s, pid)
		merging(mut s, pid)
		C.printf(c'LINUX SIGQUEUE SUMMARY: checks=%d failures=%d\n', s.checks, s.failures)
		if s.failures == 0 {
			C.puts(if reference { c'LINUX SIGQUEUE REFERENCE: PASS' } else { c'LINUX SIGQUEUE: PASS' })
		}
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
