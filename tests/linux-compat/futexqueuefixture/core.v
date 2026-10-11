// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module futexqueuefixture

#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <time.h>

@[typedef]
struct C.pthread_t {}
@[typedef]
struct C.pthread_mutex_t {}
@[typedef]
struct C.pthread_cond_t {}
struct C.timespec {
	tv_sec isize
	tv_nsec isize
}
struct Wait {
	address &i32 = unsafe { nil }
	private bool
	bitset bool
	untimed bool
	short bool
	error i32
}
fn C.pthread_create(&C.pthread_t, voidptr, fn(voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_kill(C.pthread_t, i32) i32
fn C.pthread_mutex_init(&C.pthread_mutex_t, voidptr) i32
fn C.pthread_mutex_lock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_unlock(&C.pthread_mutex_t) i32
fn C.pthread_cond_init(&C.pthread_cond_t, voidptr) i32
fn C.pthread_cond_wait(&C.pthread_cond_t, &C.pthread_mutex_t) i32
fn C.pthread_cond_broadcast(&C.pthread_cond_t) i32
fn C.syscall(isize, ...) isize
fn C.clock_gettime(i32, &C.timespec) i32
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.munmap(voidptr, usize) i32
fn C.mprotect(voidptr, usize, i32) i32
fn C.ftruncate(i32, isize) i32
fn C.close(i32) i32
fn C.sysconf(i32) isize
fn C.signal(i32, fn(i32)) voidptr
fn C.usleep(u32) i32
fn C.puts(&char) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.__errno_location() &i32
fn C.__atomic_fetch_add(&i32, i32, i32) i32
fn C.__atomic_load_n(&i32, i32) i32

__global (
	words [3]i32
	ready i32
	woke i32
	bad i32
	mutex C.pthread_mutex_t
	condition C.pthread_cond_t
	released bool
)

fn call(address &i32, operation isize, wake isize, move isize, other &i32, expected isize, result isize, error i32) bool {
	unsafe {
		errno_address := C.__errno_location()
		*errno_address = 0
		actual := C.syscall(isize(C.SYS_futex), address, operation, wake, move, other, expected)
		if actual != result || *errno_address != error {
			C.printf(c'LINUX FUTEXQUEUE FAIL: op=%ld wake=%ld move=%ld returned=%ld errno=%d expected=%ld/%d\n', operation, wake, move, actual, *errno_address, result, error)
			return false
		}
		return true
	}
}

fn waiter(argument voidptr) voidptr {
	unsafe {
		request := &Wait(argument)
		mut duration := C.timespec{tv_sec: 5}
		if request.short { duration = C.timespec{tv_nsec: 400000000} }
		if request.bitset {
			if C.clock_gettime(1, &duration) != 0 { C.__atomic_fetch_add(&bad, 1, 5); return nil }
			duration.tv_sec += 5
		}
		C.__atomic_fetch_add(&ready, 1, 5)
		timeout := if request.untimed { voidptr(nil) } else { voidptr(&duration) }
		operation := if request.bitset { isize(9) } else { isize(0) } | if request.private { isize(128) } else { isize(0) }
		actual := C.syscall(isize(C.SYS_futex), request.address, operation, isize(0), timeout, isize(0), isize(2))
		if actual != if request.error == 0 { 0 } else { -1 } || (request.error != 0 && *C.__errno_location() != request.error) {
			C.printf(c'LINUX FUTEXQUEUE FAIL: waiter result=%ld errno=%d expected-error=%d\n', actual, *C.__errno_location(), request.error)
			C.__atomic_fetch_add(&bad, 1, 5)
		} else { C.__atomic_fetch_add(&woke, 1, 5) }
	}
	return unsafe { nil }
}

fn totals(expected i32) bool {
	unsafe {
		for _ in 0..1000 {
			if C.__atomic_load_n(&woke, 5) == expected { break }
			C.usleep(1000)
		}
		C.usleep(20000)
		if C.__atomic_load_n(&woke, 5) != expected || C.__atomic_load_n(&bad, 5) != 0 {
			C.printf(c'LINUX FUTEXQUEUE FAIL: completed=%d expected=%d bad=%d\n', woke, expected, bad)
			return false
		}
		return true
	}
}

fn ready_count(expected i32) bool {
	unsafe {
		for _ in 0..1000 {
			if C.__atomic_load_n(&ready, 5) == expected { break }
			C.usleep(1000)
		}
		C.usleep(100000)
		return C.__atomic_load_n(&ready, 5) == expected
	}
}

fn signal_handler(_ i32) {}

fn condition_waiter(_ voidptr) voidptr {
	unsafe {
		if C.pthread_mutex_lock(&mutex) != 0 { C.__atomic_fetch_add(&bad, 1, 5); return nil }
		C.__atomic_fetch_add(&ready, 1, 5)
		for !released {
			if C.pthread_cond_wait(&condition, &mutex) != 0 { C.__atomic_fetch_add(&bad, 1, 5); break }
		}
		C.__atomic_fetch_add(&woke, 1, 5)
		if C.pthread_mutex_unlock(&mutex) != 0 { C.__atomic_fetch_add(&bad, 1, 5) }
	}
	return unsafe { nil }
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		// Even an empty queue must compare the word and validate both counts.
		if !call(&words[0], 132, 0, 0, &words[1], 1, -1, C.EAGAIN)
			|| !call(voidptr(1), 131, -1, 0, voidptr(1), 0, -1, C.EINVAL)
			|| !call(&words[0], 132, 0, -1, &words[1], 0, -1, C.EINVAL)
			|| !call(&words[0], 131, 0, isize(u64(1) << 32), &words[1], 0, 0, 0)
			|| !call(voidptr(1), 131, 0, 0, &words[1], 0, -1, C.EINVAL)
			|| !call(&words[0], 131, 0, 0, voidptr(1), 0, -1, C.EINVAL)
			|| !call(&words[0], 131, 0, 0, nil, 0, 0, 0)
			|| !call(nil, 132, 0, 0, &words[1], 0, -1, C.EFAULT) { return 1 }
		page := C.sysconf(C._SC_PAGESIZE)
		fd := i32(C.syscall(isize(C.SYS_memfd_create), c'futex-requeue', isize(0)))
		if page <= 0 || fd < 0 || C.ftruncate(fd, page) != 0 { return 1 }
		shared := C.mmap(nil, usize(page), 3, 1, fd, 0)
		alias := C.mmap(nil, usize(page), 3, 1, fd, 0)
		readonly := C.mmap(nil, usize(page), 3, 0x22, -1, 0)
		if shared == voidptr(-1) || alias == voidptr(-1) || readonly == voidptr(-1) { return 1 }
		*(&i32(readonly)) = 0
		if C.mprotect(readonly, usize(page), 1) != 0
			|| !call(readonly, 132, 0, 0, &words[1], 0, 0, 0)
			|| !call(readonly, 132, 0, 0, &words[1], 1, -1, C.EAGAIN) { return 1 }
		// Different keys, existing target waiters and shared virtual aliases.
		for round in 0..8 {
			ready = 0; woke = 0; bad = 0
			private := round < 4
			source := if private { &words[0] } else { &i32(shared) }
			source_alias := if private { source } else { &i32(alias) }
			target := if private { &words[1] } else { &i32(usize(shared) + 4) }
			target_alias := if private { target } else { &i32(usize(alias) + 4) }
			flag := if private { isize(128) } else { isize(0) }
			mut threads := [14]C.pthread_t{}
			mut requests := [14]Wait{}
			for i in 0..14 {
				requests[i] = Wait{address: if i < 12 { source } else { target }, private: private, bitset: round % 2 == 1, untimed: round % 3 == 1}
				if C.pthread_create(&threads[i], nil, waiter, &requests[i]) != 0 { return 1 }
			}
			if !ready_count(14)
				|| !call(source_alias, flag | 4, 2, 4, target_alias, 1, -1, C.EAGAIN)
				|| !totals(0)
				|| !call(source_alias, flag | 3, 0, 0, target_alias, 0, 0, 0)
				|| !totals(0)
				|| !call(source_alias, flag | if round % 2 == 0 { isize(3) } else { isize(4) }, 2, 4, target_alias, 0, 6, 0)
				|| !totals(2)
				|| !call(source_alias, flag | 1, 0x7fffffff, 0, nil, 0, 6, 0)
				|| !totals(8) { return 1 }
			if round % 2 == 1 && (!call(target_alias, flag | 10, 12, 0, nil, 1, 0, 0) || !totals(8)) { return 1 }
			if !call(target_alias, flag | 10, 2, 0, nil, 2, 2, 0) || !totals(10)
				|| !call(target_alias, flag | 1, 0x7fffffff, 0, nil, 0, 4, 0) || !totals(14) { return 1 }
			for worker_id in threads { if C.pthread_join(worker_id, nil) != 0 { return 1 } }
		}
		// Requeue through a second target, including same-key bounded counting.
		for round in 0..3 {
			ready = 0; woke = 0; bad = 0
			mut threads := [12]C.pthread_t{}
			mut requests := [12]Wait{}
			for i in 0..12 {
				requests[i] = Wait{address: &words[0], private: true}
				if C.pthread_create(&threads[i], nil, waiter, &requests[i]) != 0 { return 1 }
			}
			if !ready_count(12) || !call(&words[0], 131, 0, 4, &words[0], 0, 4, 0) || !totals(0)
				|| !call(&words[0], 132, 0, 12, &words[1], 0, 12, 0) || !totals(0)
				|| !call(&words[1], 131, 0, 7, &words[2], 0, 7, 0) || !totals(0)
				|| !call(&words[0], 129, 12, 0, nil, 0, 0, 0)
				|| !call(&words[1], 129, 12, 0, nil, 0, 5, 0) || !totals(5)
				|| !call(&words[2], 129, 12, 0, nil, 0, 7, 0) || !totals(12) { return 1 }
			for worker_id in threads { if C.pthread_join(worker_id, nil) != 0 { return 1 } }
		}
		// Cancellation must unlink from the new queue, retaining the original timer.
		if C.signal(C.SIGUSR1, signal_handler) == voidptr(-1) { return 1 }
		for round in 0..2 {
			ready = 0; woke = 0; bad = 0
			mut threads := [8]C.pthread_t{}
			mut requests := [8]Wait{}
			for i in 0..8 {
				requests[i] = Wait{address: &words[0], private: true, short: round == 0, error: if round == 0 { C.ETIMEDOUT } else { C.EINTR }}
				if C.pthread_create(&threads[i], nil, waiter, &requests[i]) != 0 { return 1 }
			}
			if !ready_count(8) || !call(&words[0], 131, 0, 8, &words[1], 0, 8, 0) { return 1 }
			if round == 1 { for worker_id in threads { if C.pthread_kill(worker_id, C.SIGUSR1) != 0 { return 1 } } }
			for worker_id in threads { if C.pthread_join(worker_id, nil) != 0 { return 1 } }
			if !totals(8) || !call(&words[0], 129, 8, 0, nil, 0, 0, 0)
				|| !call(&words[1], 129, 8, 0, nil, 0, 0, 0) { return 1 }
		}
		if C.pthread_mutex_init(&mutex, nil) != 0 || C.pthread_cond_init(&condition, nil) != 0 { return 1 }
		for _ in 0..20 {
			ready = 0; woke = 0; bad = 0; released = false
			mut threads := [12]C.pthread_t{}
			for i in 0..12 { if C.pthread_create(&threads[i], nil, condition_waiter, nil) != 0 { return 1 } }
			if !ready_count(12) || C.pthread_mutex_lock(&mutex) != 0 { return 1 }
			released = true
			if C.pthread_cond_broadcast(&condition) != 0 || !totals(0) || C.pthread_mutex_unlock(&mutex) != 0 { return 1 }
			for worker_id in threads { if C.pthread_join(worker_id, nil) != 0 { return 1 } }
			if !totals(12) { return 1 }
		}
		if C.munmap(shared, usize(page)) != 0 || C.munmap(alias, usize(page)) != 0 || C.munmap(readonly, usize(page)) != 0 || C.close(fd) != 0 { return 1 }
		C.puts(c'LINUX FUTEXQUEUE PASS: exact comparison/count errors, bounded and shared-alias transfers, masks, same-key/multihop, timeout/signal cleanup, 164 raw waiters and 240 musl condition waits')
		C.puts(c'LINUX FUTEXQUEUE: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
