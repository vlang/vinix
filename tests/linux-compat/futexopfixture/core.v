// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module futexopfixture

#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <time.h>

@[typedef]
struct C.pthread_t {}
struct C.timespec { tv_sec isize tv_nsec isize }
fn C.pthread_create(&C.pthread_t, voidptr, fn(voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.syscall(isize, ...) isize
fn C.usleep(u32) i32
fn C.puts(&char) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.__errno_location() &i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32

__global ( first i32 target i32 ready i32 completed i32 wait_result i32 )

fn waiter(argument voidptr) voidptr {
	unsafe {
		deadline := C.timespec{tv_sec: 5}
		value := C.__atomic_load_n(&target, 5)
		C.__atomic_store_n(&ready, 1, 5)
		actual := C.syscall(isize(C.SYS_futex), &target, isize(128), isize(value), &deadline, isize(0), isize(0))
		C.__atomic_store_n(&wait_result, i32(actual), 5)
		C.__atomic_store_n(&completed, 1, 5)
	}
	return unsafe { nil }
}

fn comparison_test(comparison u32, old i32) bool {
	unsafe {
		C.__atomic_store_n(&target, old, 5)
		C.__atomic_store_n(&ready, 0, 5)
		C.__atomic_store_n(&completed, 0, 5)
		C.__atomic_store_n(&wait_result, -2, 5)
		mut worker := C.pthread_t{}
		if C.pthread_create(&worker, nil, waiter, nil) != 0 { return false }
		for i := 0; i < 1000 && C.__atomic_load_n(&ready, 5) == 0; i++ { C.usleep(1000) }
		if C.__atomic_load_n(&ready, 5) != 1 { return false }
		C.usleep(100000)
		matched := match comparison {
			0 { old == -1 }
			1 { old != -1 }
			2 { old < -1 }
			3 { old >= -1 }
			4 { old <= -1 }
			else { old > -1 }
		}
		code := u32(0x20000fff) | comparison << 24 // OR zero; signed cmparg -1.
		actual := C.syscall(isize(C.SYS_futex), &first, isize(133), isize(1), isize(1), &target, isize(code))
		for i := 0; i < 1000 && matched && C.__atomic_load_n(&completed, 5) == 0; i++ { C.usleep(1000) }
		C.usleep(20000)
		if actual != if matched { 1 } else { 0 } || C.__atomic_load_n(&completed, 5) != if matched { 1 } else { 0 }
			|| C.__atomic_load_n(&target, 5) != old {
			C.printf(c'LINUX FUTEXOP FAIL: comparison=%u old=%d returned=%ld expected=%d\n', comparison, old, actual, if matched { 1 } else { 0 })
			return false
		}
		if !matched && C.syscall(isize(C.SYS_futex), &target, isize(129), isize(1), isize(0), isize(0), isize(0)) != 1 { return false }
		return C.pthread_join(worker, nil) == 0 && C.__atomic_load_n(&wait_result, 5) == 0
	}
}

fn atomic_test(code u32, old i32, expected i32, expected_error i32) bool {
	unsafe {
		C.__atomic_store_n(&target, old, 5)
		errno_address := C.__errno_location()
		*errno_address = 0
		actual := C.syscall(isize(C.SYS_futex), &first, isize(133), isize(1), isize(1), &target, isize(code))
		if actual != if expected_error == 0 { 0 } else { -1 }
			|| *errno_address != expected_error || C.__atomic_load_n(&target, 5) != expected {
			C.printf(c'LINUX FUTEXOP FAIL: code=%x returned=%ld errno=%d word=%d expected-word=%d expected-errno=%d\n', code, actual, *errno_address, C.__atomic_load_n(&target, 5), expected, expected_error)
			return false
		}
		return true
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		for comparison := u32(0); comparison < 6; comparison++ {
			for old in [i32(-2), i32(-1), i32(0), i32(2)]! {
				if !comparison_test(comparison, old) { return 1 }
			}
		}
		if !atomic_test(0x00003000, 7, 3, 0) // SET 3
			|| !atomic_test(0x10fff000, 7, 6, 0) // ADD -1
			|| !atomic_test(0x20008000, 7, 15, 0) // OR 8
			|| !atomic_test(0x30003000, 7, 4, 0) // ANDN 3
			|| !atomic_test(0x40002000, 7, 5, 0) { return 1 } // XOR 2
		for shift in [i32(32), i32(64), i32(-1), i32(31)]! {
			code := u32(0xa0000000) | (u32(shift) & 0xfff) << 12
			if !atomic_test(code, 0, i32(u32(1) << (u32(shift) & 31)), 0) { return 1 }
		}
		// An unsupported atomic op is refused without modification. The
		// comparison is decoded after a supported atomic op has taken effect.
		if !atomic_test(0x50003000, 7, 7, C.ENOSYS)
			|| !atomic_test(0x16003000, 7, 10, C.ENOSYS) { return 1 }
		C.puts(c'LINUX FUTEXOP PASS: all six signed comparisons, 24 actual waiters, five atomic operations, masked shifts and ENOSYS side effects')
		C.puts(c'LINUX FUTEXOP: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
