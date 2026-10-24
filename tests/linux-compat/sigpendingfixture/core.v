// SPDX-License-Identifier: GPL-2.0-or-later
module sigpendingfixture

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.sigset_t {}
struct Totals { mut: checks i32 failures i32 }
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
fn C.sigpending(&C.sigset_t) i32
fn C.sigismember(&C.sigset_t, i32) i32
fn C.sysconf(i32) isize
fn C._exit(i32)
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32

fn fatal(stage int) {
	C.printf(c'LINUX SIGPENDING FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut t Totals, good bool, stage int) {
	t.checks++
	if !good {
		t.failures++
		if t.failures <= 30 { C.printf(c'LINUX SIGPENDING MISMATCH: stage=%d\n', stage) }
	}
}
fn pending(pointer voidptr, size u64) isize {
	error_ptr := C.__errno_location()
	unsafe { *error_ptr = 0 }
	return C.syscall(isize(C.SYS_rt_sigpending), pointer, usize(size))
}
fn error_is(mut t Totals, pointer voidptr, size u64, code i32, stage int) {
	result := pending(pointer, size)
	check(mut t, result == -1 && unsafe { *C.__errno_location() } == code, stage)
}
fn prefix(mut t Totals, expected u64) {
	unsafe {
		for offset in [8, 3]! {
			for size in 0 .. 9 {
				mut output := [24]u8{init: 0xa5}
				check(mut t, pending(&output[offset], u64(size)) == 0, 10 + size)
				mut good := true
				for i in 0 .. 24 {
					value := if i >= offset && i < offset + size { u8(expected >> u64((i - offset) * 8)) } else { u8(0xa5) }
					if output[i] != value { good = false }
				}
				check(mut t, good, 20 + size)
			}
		}
	}
}

// Raw native Linux sigsets contain eight bytes even when libc sigset_t is
// larger. Short copies expose their little-endian prefix without consuming it.
fn suite(mut t Totals) {
	unsafe {
		thread_bits := (u64(1) << 9) | (u64(1) << 34)
		shared_bits := (u64(1) << 11) | (u64(1) << 47) | (u64(1) << 63)
		mut mask := thread_bits | shared_bits
		if C.syscall(isize(C.SYS_rt_sigprocmask), isize(C.SIG_BLOCK), &mask, nil, usize(8)) != 0 { fatal(1) }
		prefix(mut t, 0)
		tid := C.syscall(isize(C.SYS_gettid))
		for signal in [10, 35]! {
			if C.syscall(isize(C.SYS_tgkill), isize(C.getpid()), tid, isize(signal)) != 0 { fatal(2) }
		}
		prefix(mut t, thread_bits)
		for signal in [12, 48, 64]! { if C.kill(C.getpid(), signal) != 0 { fatal(3) } }
		prefix(mut t, mask)
		mut libc_set := C.sigset_t{}
		check(mut t, C.sigpending(&libc_set) == 0, 30)
		for signal in [10, 12, 35, 48, 64]! { check(mut t, C.sigismember(&libc_set, signal) == 1, 31) }
		for signal in [1, 9, 19, 34, 63]! { check(mut t, C.sigismember(&libc_set, signal) == 0, 32) }

		pages := usize(C.sysconf(C._SC_PAGESIZE))
		if pages < 4096 || pages > 65536 { fatal(4) }
		memory := C.mmap(nil, pages * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		readonly := C.mmap(nil, pages, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		gone := C.mmap(nil, pages, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if memory == voidptr(usize(-1)) || readonly == voidptr(usize(-1)) || gone == voidptr(usize(-1)) { fatal(5) }
		if C.mprotect(voidptr(usize(memory) + pages), pages, C.PROT_NONE) != 0 || C.munmap(gone, pages) != 0 { fatal(6) }
		mut output := u64(0)
		for pointer in [voidptr(0), voidptr(1), voidptr(usize(-1)), gone, voidptr(usize(memory) + pages), readonly, voidptr(&output)]! {
			check(mut t, pending(pointer, 0) == 0, 40)
			for size in [u64(9), 16, 128, u64(1) << 32, (u64(1) << 32) + 8, ~u64(0)]! {
				error_is(mut t, pointer, size, C.EINVAL, 41)
			}
		}
		for pointer in [voidptr(0), voidptr(1), voidptr(usize(-1)), gone, voidptr(usize(memory) + pages), readonly]! {
			for size in [u64(1), 7, 8]! { error_is(mut t, pointer, size, C.EFAULT, 42) }
		}
		for size in 1 .. 9 {
			pointer := &u8(usize(memory) + pages - usize(size))
			for i in 0 .. size { pointer[i] = 0 }
			check(mut t, pending(pointer, u64(size)) == 0, 50 + size)
			mut good := true
			for i in 0 .. size { if pointer[i] != u8(mask >> u64(i * 8)) { good = false } }
			check(mut t, good, 60 + size)
			if size < 8 { error_is(mut t, pointer, u64(size + 1), C.EFAULT, 70 + size) }
		}
		check(mut t, pending(&output, 8) == 0 && output == mask, 80)
		// The permissive length ABI belongs to sigpending, not sigprocmask.
		for size in [usize(0), 1, 7, 9]! {
			error_ptr := C.__errno_location()
			*error_ptr = 0
			result := C.syscall(isize(C.SYS_rt_sigprocmask), isize(C.SIG_BLOCK), nil, &output, size)
			check(mut t, result == -1 && *C.__errno_location() == C.EINVAL, 81)
		}
		if C.munmap(memory, pages * 2) != 0 || C.munmap(readonly, pages) != 0 { fatal(7) }
		// Leave the raised signals blocked through exit; neither root nor the
		// unprivileged cohort changes its pending set during these copy checks.
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.alarm(120)
		mut total := Totals{}
		for unprivileged in [false, true]! {
			mut pipe := [2]i32{}
			if C.pipe(&pipe[0]) != 0 { fatal(8) }
			C.fflush(nil)
			pid := C.fork()
			if pid < 0 { fatal(9) }
			if pid == 0 {
				C.close(pipe[0])
				if unprivileged && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(10) }
				mut t := Totals{}
				suite(mut t)
				if C.write(pipe[1], &t, sizeof(Totals)) != sizeof(Totals) { fatal(11) }
				C.fflush(nil); C._exit(0)
			}
			C.close(pipe[1])
			mut t := Totals{}
			if C.read(pipe[0], &t, sizeof(Totals)) != sizeof(Totals) { fatal(12) }
			mut status := i32(0)
			if C.waitpid(pid, &status, 0) != pid || status != 0 { fatal(13) }
			C.close(pipe[0])
			total.checks += t.checks; total.failures += t.failures
		}
		C.printf(c'LINUX SIGPENDING SUMMARY: checks=%d failures=%d\n', total.checks, total.failures)
		if total.failures == 0 { C.printf(c'LINUX SIGPENDING: PASS\n') } else { C.printf(c'LINUX SIGPENDING: FAIL\n') }
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
