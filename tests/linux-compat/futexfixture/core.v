// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module futexfixture

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
fn C.__atomic_fetch_add(&i32, i32, i32) i32
fn C.__atomic_load_n(&i32, i32) i32

__global ( word i32 second_word i32 ready i32 woke i32 bad i32 woke_first i32 woke_second i32 )

fn waiter(argument voidptr) voidptr {
	unsafe {
		address := if argument == nil { &word } else { &i32(argument) }
		deadline := C.timespec{tv_sec: 5}
		C.__atomic_fetch_add(&ready, 1, 5)
		if C.syscall(isize(C.SYS_futex), address, isize(128), isize(C.__atomic_load_n(address, 5)), &deadline, isize(0), isize(0)) != 0 {
			C.__atomic_fetch_add(&bad, 1, 5)
		} else {
			C.__atomic_fetch_add(&woke, 1, 5)
			if address == &word { C.__atomic_fetch_add(&woke_first, 1, 5) }
			else { C.__atomic_fetch_add(&woke_second, 1, 5) }
		}
	}
	return unsafe { nil }
}

fn wake_operation_test() bool {
	unsafe {
		ready = 0; woke = 0; bad = 0; woke_first = 0; woke_second = 0
		second_word = 1
		mut workers := [12]C.pthread_t{}
		for i in 0..workers.len {
			if C.pthread_create(&workers[i], nil, waiter, if i < 6 { nil } else { voidptr(&second_word) }) != 0 { return false }
		}
		for i := 0; i < 1000 && C.__atomic_load_n(&ready, 5) != workers.len; i++ { C.usleep(1000) }
		if C.__atomic_load_n(&ready, 5) != workers.len { return false }
		C.usleep(100000)
		// OR zero leaves the second word unchanged; NE zero selects both queues.
		first := C.syscall(isize(C.SYS_futex), &word, isize(133), isize(1), isize(2), &second_word, isize(0x21000000))
		for i := 0; i < 1000 && C.__atomic_load_n(&woke, 5) < 3; i++ { C.usleep(1000) }
		C.usleep(20000)
		if first != 3 || C.__atomic_load_n(&woke_first, 5) != 1 || C.__atomic_load_n(&woke_second, 5) != 2 {
			C.printf(c'LINUX FUTEX FAIL: WAKE_OP matched return=%ld first=%d second=%d\n', first, woke_first, woke_second)
			return false
		}
		// EQ zero is false, so only the first queue's requested two may wake.
		next := C.syscall(isize(C.SYS_futex), &word, isize(133), isize(2), isize(0x7fffffff), &second_word, isize(0x20000000))
		for i := 0; i < 1000 && C.__atomic_load_n(&woke, 5) < 5; i++ { C.usleep(1000) }
		C.usleep(20000)
		if next != 2 || C.__atomic_load_n(&woke_first, 5) != 3 || C.__atomic_load_n(&woke_second, 5) != 2 { return false }
		if !wake_count(0x7fffffff, 3, 8) { return false }
		if C.syscall(isize(C.SYS_futex), &second_word, isize(129), isize(0x7fffffff), isize(0), isize(0), isize(0)) != 4 { return false }
		for worker_id in workers { if C.pthread_join(worker_id, nil) != 0 { return false } }
		return woke == 12 && bad == 0 && second_word == 1
	}
}

fn wake_count(requested i32, expected i32, total i32) bool {
	unsafe {
		result := C.syscall(isize(C.SYS_futex), &word, isize(129), isize(requested), isize(0), isize(0), isize(0))
		if result != expected {
			C.printf(c'LINUX FUTEX FAIL: wake requested=%d returned=%ld expected=%d\n', requested, result, expected)
			return false
		}
		for i := 0; i < 1000 && C.__atomic_load_n(&woke, 5) < total; i++ { C.usleep(1000) }
		C.usleep(20000)
		if C.__atomic_load_n(&woke, 5) != total || C.__atomic_load_n(&bad, 5) != 0 {
			C.printf(c'LINUX FUTEX FAIL: woke=%d total=%d bad=%d\n', C.__atomic_load_n(&woke, 5), total, C.__atomic_load_n(&bad, 5))
			return false
		}
		return true
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		for iteration := 0; iteration < 8; iteration++ {
			ready = 0; woke = 0; bad = 0
			mut threads := [12]C.pthread_t{}
			for i in 0..threads.len {
				if C.pthread_create(&threads[i], nil, waiter, nil) != 0 { return 1 }
			}
			for i := 0; i < 1000 && C.__atomic_load_n(&ready, 5) != threads.len; i++ { C.usleep(1000) }
			if C.__atomic_load_n(&ready, 5) != threads.len { return 1 }
			C.usleep(100000)
			if !wake_count(1, 1, 1) || !wake_count(2, 2, 3)
				|| !wake_count(0, 1, 4) || !wake_count(-1, 1, 5)
				|| !wake_count(3, 3, 8) || !wake_count(0x7fffffff, 4, 12) { return 1 }
			for worker_id in threads { if C.pthread_join(worker_id, nil) != 0 { return 1 } }
		}
		if !wake_operation_test() { return 1 }
		C.puts(c'LINUX FUTEX PASS: exact wake counts, legacy zero/negative counts, WAKE_OP queues, 108 timed waiters')
		C.puts(c'LINUX FUTEX: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
