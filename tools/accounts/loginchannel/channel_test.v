// SPDX-License-Identifier: GPL-2.0-or-later
module loginchannel

import authproto
import os

fn C.socketpair(int, int, int, &i32) int
fn C.dup(int) int
fn C.dup2(int, int) int
fn C.close(int) int

$if track_heap ? {
	#include "heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn test_forged_inherited_channel_cannot_receive_a_password() {
	if os.geteuid() == 0 { return }
	previous := os.getenv('VINIX_SESSION_FD')
	defer { os.setenv('VINIX_SESSION_FD', previous, true) }
	mut sockets := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) == 0
	saved := C.dup(3)
	// Move both endpoints away from the descriptor being tested.
	local := C.fcntl(sockets[0], C.F_DUPFD, voidptr(10))
	remote := C.fcntl(sockets[1], C.F_DUPFD, voidptr(10))
	C.close(sockets[0])
	C.close(sockets[1])
	assert local >= 10 && remote >= 10
	defer {
		C.close(local)
		C.close(remote)
		if saved >= 0 {
			C.dup2(saved, 3)
			C.close(saved)
		} else {
			C.close(3)
		}
	}
	assert C.dup2(local, 3) == 3
	os.setenv('VINIX_SESSION_FD', '3', true)
	for _ in 0 .. 1000 {
		$if track_heap ? { C.vinix_heap_begin() }
		mut rejected := false
		inherited() or {
			rejected = true
			unsafe { err.free() }
		}
		assert rejected
		$if track_heap ? { assert C.vinix_heap_end() == 0 }
	}
	password := 'never disclosed'.bytes()
	name := 'person'.bytes()
	defer { unsafe {
		password.free()
		name.free()
	}
	 }
	mut refused := false
	login(name, password) or { refused = err.msg().contains('not root') }
	assert refused && password.all(it == 0)
	mut wait := C.pollfd{ fd: remote, events: C.POLLIN }
	assert C.poll(&wait, 1, 0) == 0
	os.setenv('VINIX_SESSION_FD', '10', true)
	inherited() or {
		assert err.msg().contains('no session manager')
		return
	}
	assert false
}

fn test_actual_wire_frame_preserves_literal_identity_and_contains_no_extra_fields() {
	mut sockets := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) == 0
	defer {
		C.close(sockets[0])
		C.close(sockets[1])
	}
	name := 'name;literal'.bytes()
	password := 'secret ; literal'.bytes()
	defer { unsafe {
		name.free()
		password.free()
	}
	 }
	write_login(sockets[0], name, password)!
	mut frame := authproto.read_frame(sockets[1])!
	defer { frame.close() }
	assert frame.code == op_login && frame.fields.len == 2
	assert frame.fields[0] == name && frame.fields[1] == password
}
