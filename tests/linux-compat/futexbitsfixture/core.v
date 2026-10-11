// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module futexbitsfixture

#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <time.h>

@[typedef]
struct C.pthread_t {}
struct C.timespec {
	tv_sec isize
	tv_nsec isize
}
struct Wait {
	mask u32
	group int
	plain bool
	untimed bool
}
fn C.pthread_create(&C.pthread_t, voidptr, fn(voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.syscall(isize, ...) isize
fn C.clock_gettime(i32, &C.timespec) i32
fn C.usleep(u32) i32
fn C.puts(&char) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.__errno_location() &i32
fn C.__atomic_fetch_add(&i32, i32, i32) i32
fn C.__atomic_load_n(&i32, i32) i32

__global ( word i32 ready i32 bad i32 woke [3]i32 )

fn waiter(argument voidptr) voidptr {
	unsafe {
		request := &Wait(argument)
		mut deadline := C.timespec{tv_sec: 5}
		if !request.plain {
			if C.clock_gettime(1, &deadline) != 0 { C.__atomic_fetch_add(&bad, 1, 5); return nil }
			deadline.tv_sec += 5
		}
		C.__atomic_fetch_add(&ready, 1, 5)
		timeout := if request.untimed { voidptr(nil) } else { voidptr(&deadline) }
		if C.syscall(isize(C.SYS_futex), &word, if request.plain { isize(128) } else { isize(137) }, isize(0), timeout, isize(0), isize(request.mask)) != 0 {
			C.__atomic_fetch_add(&bad, 1, 5)
		} else { C.__atomic_fetch_add(&woke[request.group], 1, 5) }
	}
	return unsafe { nil }
}

fn wake(mask isize, count i32, expected i32, totals [3]i32) bool {
	unsafe {
		actual := C.syscall(isize(C.SYS_futex), &word, isize(138), isize(count), isize(0), isize(0), mask)
		if actual != expected {
			C.printf(c'LINUX FUTEXBITS FAIL: mask=%ld requested=%d returned=%ld expected=%d\n', mask, count, actual, expected)
			return false
		}
		for iteration := 0; iteration < 1000; iteration++ {
			if C.__atomic_load_n(&woke[0], 5) == totals[0] && C.__atomic_load_n(&woke[1], 5) == totals[1]
				&& C.__atomic_load_n(&woke[2], 5) == totals[2] { break }
			C.usleep(1000)
		}
		C.usleep(20000)
		for i in 0..3 { if C.__atomic_load_n(&woke[i], 5) != totals[i] { return false } }
		return C.__atomic_load_n(&bad, 5) == 0
	}
}

fn invalid_zero_mask(operation isize, mask isize) bool {
	unsafe {
		mut deadline := C.timespec{}
		errno_address := C.__errno_location()
		*errno_address = 0
		actual := C.syscall(isize(C.SYS_futex), &word, operation, isize(1), &deadline, isize(0), mask)
		if actual != -1 || *errno_address != C.EINVAL {
			C.printf(c'LINUX FUTEXBITS FAIL: zero mask op=%ld returned=%ld errno=%d\n', operation, actual, *errno_address)
			return false
		}
		return true
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		for round := 0; round < 4; round++ {
			ready = 0; bad = 0; woke = [3]i32{}
			mut threads := [12]C.pthread_t{}
			mut requests := [12]Wait{}
			for i in 0..threads.len {
				requests[i] = Wait{mask: u32(1) << u32(i % 3), group: i % 3, plain: round == 3, untimed: round == 1}
				if C.pthread_create(&threads[i], nil, waiter, voidptr(&requests[i])) != 0 { return 1 }
			}
			for i := 0; i < 1000 && C.__atomic_load_n(&ready, 5) != threads.len; i++ { C.usleep(1000) }
			if C.__atomic_load_n(&ready, 5) != threads.len { return 1 }
			C.usleep(100000)
			if round != 3 {
				if !wake(8, 1, 0, [0, 0, 0]!) { return 1 }
				for mask in [isize(0), isize(u64(1) << 32)]! {
					if !invalid_zero_mask(137, mask) || !invalid_zero_mask(138, mask) { return 1 }
				}
				if !wake(1, 1, 1, [1, 0, 0]!) || !wake(2, 3, 3, [1, 3, 0]!)
					|| !wake(1, 1, 1, [2, 3, 0]!) || !wake(4, 0x7fffffff, 4, [2, 3, 4]!)
					|| !wake(3, 0x7fffffff, 3, [4, 4, 4]!) { return 1 }
			} else {
				// Plain WAIT uses MATCH_ANY, including the highest mask bit.
				actual := C.syscall(isize(C.SYS_futex), &word, isize(138), isize(0x7fffffff), isize(0), isize(0), isize(u32(0x80000000)))
				if actual != 12 { return 1 }
			}
			for worker_id in threads { if C.pthread_join(worker_id, nil) != 0 { return 1 } }
			if bad != 0 || woke[0] != 4 || woke[1] != 4 || woke[2] != 4 { return 1 }
		}
		C.puts(c'LINUX FUTEXBITS PASS: selective masks, counted wakes, zero-mask EINVAL and u32 narrowing, plain WAIT matches all bits, 36 timed and 12 untimed waits')
		C.puts(c'LINUX FUTEXBITS: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
