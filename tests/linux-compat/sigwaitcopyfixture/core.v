// SPDX-License-Identifier: GPL-2.0-or-later
module sigwaitcopyfixture

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct Totals { mut: checks i32 failures i32 }
struct Timeout { sec i64 nsec i64 }
struct TimerSpec { interval Timeout value Timeout }
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
fn C.sysconf(i32) isize
fn C._exit(i32)
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32

fn fatal(stage int) {
	C.printf(c'LINUX SIGWAITCOPY FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut t Totals, good bool, stage int) {
	t.checks++
	if !good {
		t.failures++
		if t.failures <= 30 { C.printf(c'LINUX SIGWAITCOPY MISMATCH: stage=%d\n', stage) }
	}
}
fn bit(signal int) u64 { return u64(1) << u64(signal - 1) }
fn wait(signal int, pointer voidptr) isize {
	mut wanted := bit(signal)
	mut timeout := Timeout{}
	error_ptr := C.__errno_location()
	unsafe { *error_ptr = 0 }
	return C.syscall(isize(C.SYS_rt_sigtimedwait), &wanted, pointer, &timeout, usize(8))
}
fn pending() u64 {
	mut output := u64(0)
	if C.syscall(isize(C.SYS_rt_sigpending), &output, usize(8)) != 0 { fatal(1) }
	return output
}

// A periodic timer must become eligible again after its first notification is
// consumed by a faulting copy. Rearming would hide a missing acknowledgement.
fn timer_after_fault(mut t Totals, mask u64) {
	unsafe {
		mut event := [8]u64{}
		event[0] = 0x1234abcd
		event[1] = u64(35) | (u64(4) << 32) // SIGEV_THREAD_ID
		event[2] = u64(C.syscall(isize(C.SYS_gettid)))
		mut timer := i32(-1)
		if C.syscall(isize(C.SYS_timer_create), isize(1), &event[0], &timer) != 0 { fatal(30) }
		spec := TimerSpec{interval: Timeout{sec: 2}, value: Timeout{nsec: 1000000}}
		if C.syscall(isize(C.SYS_timer_settime), isize(timer), isize(0), &spec, nil) != 0 { fatal(31) }
		mut wanted := bit(35)
		limit := Timeout{sec: 3}
		result := C.syscall(isize(C.SYS_rt_sigtimedwait), &wanted, voidptr(1), &limit, usize(8))
		check(mut t, result == -1 && *C.__errno_location() == C.EFAULT, 30)
		check(mut t, pending() == 0, 31)
		mut output := [16]u64{}
		empty := wait(35, &output[0])
		check(mut t, empty == -1 && *C.__errno_location() == C.EAGAIN, 32)
		next := C.syscall(isize(C.SYS_rt_sigtimedwait), &wanted, &output[0], &limit, usize(8))
		check(mut t, next == 35, 33)
		check(mut t, u32(output[0]) == 35 && i32(u32(output[1])) == -2 && output[3] == event[0], 34)
		check(mut t, C.syscall(isize(C.SYS_timer_delete), isize(timer)) == 0, 35)
		check(mut t, pending() == 0, 36)
		mut current_mask := u64(0)
		check(mut t, C.syscall(isize(C.SYS_rt_sigprocmask), isize(C.SIG_BLOCK), nil, &current_mask, usize(8)) == 0 && current_mask == mask, 37)
	}
}
fn exercise(mut t Totals, signal int, shared bool, pointer voidptr, fault bool, mask u64) {
	unsafe {
		other := if signal == 10 { 12 } else { 10 }
		if C.kill(C.getpid(), other) != 0 { fatal(2) }
		if shared {
			if C.kill(C.getpid(), signal) != 0 { fatal(3) }
		} else {
			if C.syscall(isize(C.SYS_tgkill), isize(C.getpid()), C.syscall(isize(C.SYS_gettid)), isize(signal)) != 0 { fatal(4) }
		}
		check(mut t, pending() == (bit(signal) | bit(other)), 10)
		result := wait(signal, pointer)
		check(mut t, if fault { result == -1 && *C.__errno_location() == C.EFAULT } else { result == signal }, 11)
		check(mut t, pending() == bit(other), 12)
		mut output := [128]u8{}
		result2 := wait(signal, &output[0])
		check(mut t, result2 == -1 && *C.__errno_location() == C.EAGAIN, 13)
		check(mut t, wait(other, nil) == other, 14)
		check(mut t, pending() == 0, 15)
		mut current_mask := u64(0)
		check(mut t, C.syscall(isize(C.SYS_rt_sigprocmask), isize(C.SIG_BLOCK), nil, &current_mask, usize(8)) == 0 && current_mask == mask, 16)
	}
}

// Linux dequeues before copying siginfo_t. EFAULT consumes the selected signal,
// preserves other pending signals and leaves the thread's blocked mask intact.
fn suite(mut t Totals) {
	unsafe {
		mut mask := bit(10) | bit(12) | bit(35) | bit(48) | bit(64)
		if C.syscall(isize(C.SYS_rt_sigprocmask), isize(C.SIG_SETMASK), &mask, nil, usize(8)) != 0 { fatal(5) }
		pages := usize(C.sysconf(C._SC_PAGESIZE))
		if pages < 4096 || pages > 65536 { fatal(6) }
		memory := C.mmap(nil, pages * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		readonly := C.mmap(nil, pages, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		gone := C.mmap(nil, pages, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if memory == voidptr(usize(-1)) || readonly == voidptr(usize(-1)) || gone == voidptr(usize(-1)) { fatal(7) }
		if C.mprotect(voidptr(usize(memory) + pages), pages, C.PROT_NONE) != 0 || C.munmap(gone, pages) != 0 { fatal(8) }
		for pointer in [voidptr(1), voidptr(usize(-1)), gone, voidptr(usize(memory) + pages), readonly, voidptr(usize(memory) + pages - 64)]! {
			result := wait(35, pointer)
			check(mut t, result == -1 && *C.__errno_location() == C.EAGAIN, 20)
		}
		for shared in [false, true]! {
			for signal in [10, 12, 35, 48, 64]! {
				for pointer in [voidptr(1), voidptr(usize(-1)), gone, voidptr(usize(memory) + pages), readonly, voidptr(usize(memory) + pages - 64)]! {
					exercise(mut t, signal, shared, pointer, true, mask)
				}
				for offset in [8, 3]! {
					mut output := [144]u8{init: 0xa5}
					exercise(mut t, signal, shared, &output[offset], false, mask)
					mut good := output[offset] == u8(signal) && output[offset + 1] == 0 && output[offset + 2] == 0 && output[offset + 3] == 0
					for i in 0 .. 144 { if (i < offset || i >= offset + 128) && output[i] != 0xa5 { good = false } }
					check(mut t, good, 21)
				}
				last := &u8(usize(memory) + pages - 128)
				exercise(mut t, signal, shared, last, false, mask)
				check(mut t, last[0] == u8(signal) && last[1] == 0 && last[2] == 0 && last[3] == 0, 22)
				exercise(mut t, signal, shared, nil, false, mask)
			}
		}
		timer_after_fault(mut t, mask)
		if C.munmap(memory, pages * 2) != 0 || C.munmap(readonly, pages) != 0 { fatal(9) }
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
		C.printf(c'LINUX SIGWAITCOPY SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
		if total.failures == 0 { C.printf(c'LINUX SIGWAITCOPY: PASS\n') } else { C.printf(c'LINUX SIGWAITCOPY: FAIL\n') }
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
