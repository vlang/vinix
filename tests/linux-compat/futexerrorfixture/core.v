// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module futexerrorfixture

#include <errno.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <time.h>

struct C.timespec {
	tv_sec isize
	tv_nsec isize
}
fn C.syscall(isize, ...) isize
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.munmap(voidptr, usize) i32
fn C.sysconf(i32) isize
fn C.puts(&char) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.__errno_location() &i32

__global ( word i32 second i32 checks i32 )

fn check(address voidptr, operation isize, expected isize, timeout voidptr, other voidptr, bits isize, expected_error i32) bool {
	unsafe {
		errno_address := C.__errno_location()
		*errno_address = 0
		actual := C.syscall(isize(C.SYS_futex), address, operation, expected, timeout, other, bits)
		if actual != if expected_error == 0 { 0 } else { -1 } || *errno_address != expected_error {
			C.printf(c'LINUX FUTEXERROR FAIL: op=%ld returned=%ld errno=%d expected-errno=%d check=%d\n', operation, actual, *errno_address, expected_error, checks)
			return false
		}
		checks++
		return true
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		mut zero := C.timespec{}
		unaligned := voidptr(usize(&word) + 1)
		for operation in [isize(128), isize(129), isize(137), isize(138)]! {
			if !check(unaligned, operation, 1, nil, nil, 1, C.EINVAL) { return 1 }
		}
		// Unknown command bits remain part of the command; only the known
		// PRIVATE and CLOCK_REALTIME bits are stripped.
		for operation in [isize(0x280), isize(0x281), isize(0x201), isize(0x7f)]! {
			if !check(unaligned, operation, 1, nil, nil, 1, C.ENOSYS) { return 1 }
		}
		for operation in [isize(384), isize(385), isize(386), isize(389), isize(394)]! {
			if !check(unaligned, operation, 1, nil, nil, 1, C.ENOSYS) { return 1 }
		}
		if !check(&word, isize((u64(1) << 32) | 129), 1, nil, nil, 0, 0) { return 1 }
		// Private wakes need a canonical address, not a mapped page. Shared
		// operations resolve the word before treating an empty queue as success.
		page := C.sysconf(C._SC_PAGESIZE)
		unmapped := C.mmap(nil, usize(page), 3, 0x22, -1, 0)
		if page <= 0 || unmapped == voidptr(-1) || C.munmap(unmapped, usize(page)) != 0 { return 1 }
		if !check(unmapped, 129, 1, nil, nil, 0, 0)
			|| !check(unmapped, 1, 1, nil, nil, 0, C.EFAULT)
			|| !check(unmapped, 10, 1, nil, nil, 1, C.EFAULT)
			|| !check(voidptr(u64(0xfffffffffffff000)), 129, 1, nil, nil, 0, C.EFAULT) { return 1 }
		// A supplied timeout is copied/validated before bitset and address checks.
		for operation in [isize(128), isize(137), isize(134), isize(139), isize(141)]! {
			if !check(&word, operation, 1, voidptr(1), nil, 0, C.EFAULT) { return 1 }
		}
		for value in [C.timespec{tv_sec: -1}, C.timespec{tv_nsec: -1}, C.timespec{tv_nsec: 1000000000}]! {
			if !check(&word, 137, 1, voidptr(&value), nil, 0, C.EINVAL) { return 1 }
		}
		// Word comparison and bad-word errors precede deadline expiration.
		for operation in [isize(128), isize(137), isize(393)]! {
			if !check(&word, operation, 1, &zero, nil, 1, C.EAGAIN)
				|| !check(&word, operation, 0, &zero, nil, 1, C.ETIMEDOUT)
				|| !check(unmapped, operation, 0, &zero, nil, 1, C.EFAULT) { return 1 }
		}
		// WAKE_OP validates both addresses before decoding or modifying a word.
		second = 7
		if !check(unaligned, 133, 1, nil, &second, 0x10001000, C.EINVAL)
			|| !check(&word, 133, 1, nil, unaligned, 0x50000000, C.EINVAL)
			|| !check(&word, 5, 1, nil, unmapped, 0x50000000, C.EFAULT)
			|| second != 7 { return 1 }
		C.printf(c'LINUX FUTEXERROR PASS: %d alignment, flags, mapped/shared keys, timeout precedence and expired-deadline checks\n', checks)
		C.puts(c'LINUX FUTEXERROR: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
