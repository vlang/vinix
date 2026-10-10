// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

fn select_checks_call(native bool, count i32, r voidptr, w voidptr, x voidptr, timeout &DarwinSelectTime) i32 {
	$if macos {
		if native { return C.select(count, r, w, x, voidptr(timeout)) }
	}
	return darwin_select(count, r, w, x, timeout)
}

fn select_checks_bits(native bool) {
	mut pair := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, unsafe { &pair[0] }) == 0
	defer {
		C.close(pair[0])
		C.close(pair[1])
	}
	assert C.send(pair[0], c'X', 1, 0) == 1
	mut r := [34]u32{}
	mut w := [34]u32{}
	mut x := [34]u32{}
	r[0] = 0x12345678
	r[33] = 0x87654321
	w[0] = r[0]
	w[33] = r[33]
	x[0] = r[0]
	x[33] = r[33]
	r[1 + pair[1] / 32] = u32(1) << u32(pair[1] % 32)
	w[1 + pair[1] / 32] = r[1 + pair[1] / 32]
	zero := DarwinSelectTime{0, 0, 0x12345678}
	darwin_set_errno(177)
	assert select_checks_call(native, pair[1] + 1, unsafe { &r[1] }, unsafe { &w[1] }, unsafe { &x[1] }, unsafe { &zero }) == 2
	assert unsafe { *C.ios_errno_address() } == 177
	assert zero.padding == 0x12345678 && zero.seconds == 0 && zero.micros == 0
	assert r[1 + pair[1] / 32] == u32(1) << u32(pair[1] % 32)
	assert w[1 + pair[1] / 32] == r[1 + pair[1] / 32]
	assert r[0] == 0x12345678 && r[33] == 0x87654321 && w[0] == r[0] && w[33] == r[33]
	assert x[0] == r[0] && x[33] == r[33]
	for i in 1 .. 33 { r[i] = 0xffffffff }
	assert select_checks_call(native, 0, unsafe { &r[1] }, unsafe { nil }, unsafe { nil }, unsafe { &zero }) == 0
	for i in 1 .. 33 {
		assert r[i] == 0xffffffff
	}
	r[1] = 1 << 20
	r[2] = 0x12345678
	assert select_checks_call(native, 1, unsafe { &r[1] }, unsafe { nil }, unsafe { nil }, unsafe { &zero }) == 0
	assert r[1] == 0 && r[2] == 0x12345678
	assert select_checks_call(native, -1, unsafe { &r[1] }, unsafe { nil }, unsafe { nil }, unsafe { &zero }) == -1
	assert unsafe { *C.ios_errno_address() } == 22
	assert r[1] == 0 && r[2] == 0x12345678
	assert select_checks_call(native, 1025, unsafe { &r[1] }, unsafe { nil }, unsafe { nil }, unsafe { &zero }) == -1
	assert unsafe { *C.ios_errno_address() } == 22
	for invalid in [DarwinSelectTime{-1, 0, 0}, DarwinSelectTime{0, -1, 0},
		DarwinSelectTime{0, 1000000, 0}] {
		assert select_checks_call(native, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }, unsafe { &invalid }) == -1
		assert unsafe { *C.ios_errno_address() } == 22
	}
	closed := C.dup(pair[1])
	assert closed >= 0 && closed < 1024
	assert C.close(closed) == 0
	for i in 1 .. 33 { r[i] = 0 }
	r[1 + closed / 32] = u32(1) << u32(closed % 32)
	before := r
	assert select_checks_call(native, closed + 1, unsafe { &r[1] }, unsafe { nil }, unsafe { nil }, unsafe { &zero }) == -1
	assert unsafe { *C.ios_errno_address() } == 9 && r == before
	interval := DarwinSelectTime{0, 20000, 0x12345678}
	start := time.sys_mono_now()
	assert select_checks_call(native, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }, unsafe { &interval }) == 0
	assert time.sys_mono_now() - start >= 15000000
	assert interval.seconds == 0 && interval.micros == 20000 && interval.padding == 0x12345678
	// Set the last bit at the actual descriptor boundary, not an invented fd.
	high := C.fcntl(pair[1], C.F_DUPFD, usize(1023))
	assert high == 1023
	defer { C.close(high) }
	for i in 1 .. 33 { r[i] = 0 }
	r[32] = 0x80000000
	assert select_checks_call(native, 1024, unsafe { &r[1] }, unsafe { nil }, unsafe { nil }, unsafe { &zero }) == 1
	assert r[32] == 0x80000000 && r[33] == 0x87654321
}

fn select_delayed_send(fd i32) {
	time.sleep(30 * time.millisecond)
	assert C.send(fd, c'Y', 1, 0) == 1
}

fn select_checks_blocking(native bool) {
	mut pair := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, unsafe { &pair[0] }) == 0
	defer {
		C.close(pair[0])
		C.close(pair[1])
	}
	mut bits := [32]u32{}
	bits[pair[1] / 32] = u32(1) << u32(pair[1] % 32)
	worker := spawn select_delayed_send(pair[0])
	assert select_checks_call(native, pair[1] + 1, unsafe { &bits[0] }, unsafe { nil }, unsafe { nil }, unsafe { nil }) == 1
	worker.wait()
	mut byte := u8(0)
	assert C.recv(pair[1], unsafe { &byte }, 1, 0) == 1 && byte == 0x59
	assert C.close(pair[0]) == 0
	pair[0] = -1
	bits[pair[1] / 32] = u32(1) << u32(pair[1] % 32)
	zero := DarwinSelectTime{}
	assert select_checks_call(native, pair[1] + 1, unsafe { &bits[0] }, unsafe { nil }, unsafe { nil }, unsafe { &zero }) == 1
	assert C.recv(pair[1], unsafe { &byte }, 1, 0) == 0
}

fn test_darwin_select() {
	$if macos {
		select_checks_bits(true)
		select_checks_blocking(true)
	}
	select_checks_bits(false)
	select_checks_blocking(false)
	mut jobs := []thread{}
	darwin_set_errno(12345)
	for _ in 0 .. 8 { jobs << spawn select_checks_blocking(false) }
	jobs.wait()
	assert unsafe { *C.ios_errno_address() } == 12345
	address := sockets_symbol('_select') or { panic('select resolver missing') }
	assert address == u64(unsafe { voidptr(darwin_select) })
	println('IOS-SELECT: native readiness, count, bitmap guards, timeout, errors, EOF and eight workers')
}
