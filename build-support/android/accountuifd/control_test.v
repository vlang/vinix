// SPDX-License-Identifier: GPL-2.0-or-later
module accountuifd

import time

fn C.recvmsg(int, &C.msghdr, int) isize
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize

fn test_control_pair_normalizes_closed_standard_streams() {
	pid := C.fork()
	assert pid >= 0
	if pid == 0 {
		C.close(0)
		C.close(1)
		C.close(2)
		pair := socket_pair() or {
			C._exit(1)
			return
		}
		if pair[0] < 3 || pair[1] < 3 || pair[0] == pair[1]
			|| C.fcntl(pair[0], C.F_GETFD) & C.FD_CLOEXEC == 0
			|| C.fcntl(pair[1], C.F_GETFD) & C.FD_CLOEXEC == 0 {
			C._exit(2)
		}
		C.close(pair[0])
		C.close(pair[1])
		C._exit(0)
	}
	mut status := i32(0)
	assert wait_helper(pid, &status, 0) == pid && status == 0
}

fn test_ready_child_handoff_then_lifetime_eof_and_reap() {
	control := socket_pair() or { panic(err) }
	defer { C.close(control[1]) }
	life := socket_pair() or { panic(err) }
	mut pipe := [i32(-1), i32(-1)]!
	assert C.pipe(&pipe[0]) == 0
	surface := C.open(c'/dev/null', C.O_RDWR)
	assert surface >= 3
	pid := C.fork()
	assert pid >= 0
	if pid == 0 {
		C.close(control[0])
		C.close(control[1])
		C.close(life[0])
		C.close(surface)
		C.close(pipe[0])
		C.close(pipe[1])
		byte := u8(1)
		if C.write(life[1], &byte, 1) != 1 { C._exit(1) }
		mut input := u8(0)
		if C.read(life[1], &input, 1) != 0 { C._exit(2) }
		C.close(life[1])
		C._exit(0)
	}
	C.close(life[1])
	C.close(pipe[1])
	mut controller := Controller{
		fd:         control[0]
		config:     Config{ helper: '/unused'.clone(), window_socket: '/unused'.clone() }
		pid:        pid
		lifetime:   life[0]
		surface:    surface
		input:      pipe[0]
		session:    31
		capability: []u8{len: 32, init: u8(index + 1)}
		pending:    true
		used:       true
		deadline:   time.sys_mono_now() + time.second
	}
	defer { controller.close() }
	mut ready := false
	deadline := time.sys_mono_now() + time.second
	for time.sys_mono_now() < deadline {
		tick := controller.tick() or { panic(err) }
		assert !tick.ended
		if tick.ready {
			ready = true
			assert tick.session == 31
			break
		}
		time.sleep(time.millisecond)
	}
	assert ready
	mut received := [64]u8{}
	mut ancillary := [8]u64{}
	mut iov := C.iovec{ iov_base: unsafe { &received[0] }, iov_len: 64 }
	mut message := C.msghdr{
		msg_iov:        &iov
		msg_iovlen:     1
		msg_control:    unsafe { &ancillary[0] }
		msg_controllen: sizeof(ancillary)
	}
	assert C.recvmsg(control[1], &message, C.MSG_DONTWAIT) == 64
	header := C.CMSG_FIRSTHDR(&message)
	assert header != unsafe { nil } && header.cmsg_len == C.CMSG_LEN(2 * sizeof(i32))
	mut descriptors := [i32(-1), i32(-1)]!
	unsafe { C.memcpy(&descriptors[0], C.CMSG_DATA(header), 2 * sizeof(i32)) }
	C.close(descriptors[0])
	C.close(descriptors[1])
	assert controller.surface == -1 && controller.input == -1
	controller.end(31)
	assert controller.active_session() == 0
	for time.sys_mono_now() < deadline && controller.pid > 0 {
		controller.tick() or { panic(err) }
		time.sleep(time.millisecond)
	}
	assert controller.pid == -1
}

fn test_frame_binds_private_session_and_geometry() {
	cap := []u8{len: 32, init: u8(index + 1)}
	bytes := frame(0x0102030405060708, cap, 480, 640) or { panic(err) }
	defer {
		unsafe {
			cap.free()
			bytes.free()
		}
	}
	assert bytes.len == 64
	assert bytes[..4].bytestr() == 'WSUI'
	assert bytes[4..8] == [u8(0), 1, 0, 0]
	assert bytes[8..16] == [u8(1), 2, 3, 4, 5, 6, 7, 8]
	assert bytes[16..48] == cap
	assert bytes[48..] == [u8(0), 0, 1, 224, 0, 0, 2, 128, 0, 0, 7, 128, 0, 0, 0, 0]
	if _ := frame(0, cap, 480, 640) {
		assert false
	}
	if _ := frame(1, cap, 63, 640) {
		assert false
	}
	if _ := frame(1, cap, 480, 4097) {
		assert false
	}
	if _ := frame(1, []u8{len: 32}, 480, 640) {
		assert false
	}
}

fn test_scm_rights_delivers_two_actual_descriptors() {
	mut socket := [i32(-1), i32(-1)]!
	mut pipe := [i32(-1), i32(-1)]!
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &socket[0]) == 0
	defer {
		C.close(socket[0])
		C.close(socket[1])
	}
	assert C.pipe(&pipe[0]) == 0
	defer {
		C.close(pipe[0])
		C.close(pipe[1])
	}
	cap := []u8{len: 32, init: u8(index + 1)}
	bytes := frame(1, cap, 480, 640) or { panic(err) }
	defer {
		unsafe {
			cap.free()
			bytes.free()
		}
	}
	send_descriptors(socket[0], bytes, pipe[0], pipe[1]) or { panic(err) }
	mut received := [64]u8{}
	mut control := [8]u64{}
	mut iov := C.iovec{ iov_base: unsafe { &received[0] }, iov_len: 64 }
	mut message := C.msghdr{
		msg_iov:        &iov
		msg_iovlen:     1
		msg_control:    unsafe { &control[0] }
		msg_controllen: sizeof(control)
	}
	assert C.recvmsg(socket[1], &message, 0) == 64
	assert received[..] == bytes
	header := C.CMSG_FIRSTHDR(&message)
	assert header != unsafe { nil }
	assert header.cmsg_level == C.SOL_SOCKET && header.cmsg_type == C.SCM_RIGHTS
	assert header.cmsg_len == C.CMSG_LEN(2 * sizeof(i32))
	mut descriptors := [i32(-1), i32(-1)]!
	unsafe { C.memcpy(&descriptors[0], C.CMSG_DATA(header), 2 * sizeof(i32)) }
	defer {
		C.close(descriptors[0])
		C.close(descriptors[1])
	}
	assert descriptors[0] != pipe[0] && descriptors[1] != pipe[1]
	byte := u8(37)
	assert C.write(descriptors[1], &byte, 1) == 1
	mut read := u8(0)
	assert C.read(descriptors[0], &read, 1) == 1 && read == byte
}

fn test_linux_surface_size_cannot_change_after_provisioning() {
	$if linux {
		fd := sealed_surface(480, 640) or { panic(err) }
		defer { C.close(fd) }
		assert C.fcntl(fd, 1034) & 6 == 6
		assert C.ftruncate(fd, 48) != 0
		assert C.ftruncate(fd, 48 + 480 * 640 * 8 + 1) != 0
	}
}
