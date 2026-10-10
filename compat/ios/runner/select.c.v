// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <sys/select.h>

struct C.fd_set {}

fn C.select(i32, &C.fd_set, &C.fd_set, &C.fd_set, &C.timeval) i32

struct DarwinSelectTime {
	seconds i64
	micros  i32
	padding i32
}

fn select_has(set &u64, fd i32) bool {
	return unsafe { set[fd / 64] & (u64(1) << u32(fd % 64)) != 0 }
}

fn darwin_select(count i32, reads voidptr, writes voidptr, excepts voidptr, timeout &DarwinSelectTime) i32 {
	// Both the measured Mac ABI and native Vinix backend allow 1024 bits.
	if count < 0 || count > 1024 {
		darwin_set_errno(22)
		return -1
	}
	previous := unsafe { *C.ios_errno_address() }
	mut time := C.timeval{}
	mut time_ptr := &C.timeval(unsafe { nil })
	if timeout != unsafe { nil } {
		if timeout.seconds < 0 || timeout.micros < 0 || timeout.micros >= 1000000 {
			darwin_set_errno(22)
			return -1
		}
		time = C.timeval{ tv_sec: u64(timeout.seconds), tv_usec: u64(timeout.micros) }
		time_ptr = unsafe { &time }
	}
	// Darwin reads/writes 32-bit words; Linux uses 64-bit words. Copy only
	// the caller's Darwin prefix into zeroed native stack sets, and keep all
	// outputs private until success. The input timeval is never written back.
	size := usize((count + 31) / 32) * 4
	mut read_set := [16]u64{}
	mut write_set := [16]u64{}
	mut except_set := [16]u64{}
	if size != 0 {
		unsafe {
			if reads != nil { C.memcpy(&read_set[0], reads, size) }
			if writes != nil { C.memcpy(&write_set[0], writes, size) }
			if excepts != nil { C.memcpy(&except_set[0], excepts, size) }
		}
	}
	if count % 64 != 0 {
		mask := (u64(1) << u32(count % 64)) - 1
		read_set[count / 64] &= mask
		write_set[count / 64] &= mask
		except_set[count / 64] &= mask
	}
	for fd := i32(0); fd < count; fd++ {
		if select_has(unsafe { &read_set[0] }, fd) || select_has(unsafe { &write_set[0] }, fd)
			|| select_has(unsafe { &except_set[0] }, fd) {
			// Native pselect can omit POLLNVAL rather than fail. Validate actual
			// descriptors first, without changing the application's sets.
			if C.fcntl(fd, C.F_GETFD, usize(0)) < 0 { return i32(socket_result(-1)) }
		}
	}
	result := C.select(count,
		if reads == unsafe { nil } { unsafe { nil } } else { unsafe { &C.fd_set(&read_set[0]) } },
		if writes == unsafe { nil } { unsafe { nil } } else { unsafe { &C.fd_set(&write_set[0]) } },
		if excepts == unsafe { nil } {
			unsafe { nil }
		} else {
			unsafe { &C.fd_set(&except_set[0]) }
		}, time_ptr)
	if result < 0 { return i32(socket_result(result)) }
	// Darwin counts each ready bit, including one fd in multiple sets. Vinix
	// returns the number of distinct fds; derive the count from native outputs.
	mut ready := i32(0)
	for fd := i32(0); fd < count; fd++ {
		if reads != unsafe { nil } && select_has(unsafe { &read_set[0] }, fd) { ready++ }
		if writes != unsafe { nil } && select_has(unsafe { &write_set[0] }, fd) { ready++ }
		if excepts != unsafe { nil } && select_has(unsafe { &except_set[0] }, fd) { ready++ }
	}
	if size != 0 {
		unsafe {
			if reads != nil { C.memcpy(reads, &read_set[0], size) }
			if writes != nil { C.memcpy(writes, &write_set[0], size) }
			if excepts != nil { C.memcpy(excepts, &except_set[0], size) }
		}
	}
	darwin_set_errno(previous)
	return ready
}
