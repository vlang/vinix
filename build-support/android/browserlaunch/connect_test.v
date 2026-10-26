// SPDX-License-Identifier: GPL-2.0-or-later
module browserlaunch

import os
import time

fn x11_test_fd_count() int {
	mut count := 0
	for fd in 0 .. 4096 { if C.fcntl(i32(fd), C.F_GETFD) >= 0 { count++ } }
	return count
}

fn x11_test_bound_socket(path string) !i32 {
	mut address := C.sockaddr_un{}
	$if macos {
		address.sun_len = u8(sizeof(C.sockaddr_un))
	}
	address.sun_family = C.AF_UNIX
	assert path.len < address.sun_path.len && !os.exists(path)
	for index, byte in path { address.sun_path[index] = char(byte) }
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return error('test socket failed') }
	if C.bind(fd, voidptr(&address), u32(sizeof(C.sockaddr_un))) != 0 {
		C.close(fd)
		return error('test bind failed')
	}
	return fd
}

fn test_x11_connect_failures_do_not_leak_descriptors() {
	path := '/tmp/vinix-x11-connect-${C.getpid()}.sock'
	assert !os.exists(path)
	initial := x11_test_fd_count()
	for _ in 0 .. 64 {
		mut rejected := false
		x11_connect(path, 50) or {
			rejected = true
			i32(-1)
		}
		assert rejected
	}
	assert x11_test_fd_count() == initial
	bound := x11_test_bound_socket(path)!
	defer {
		C.close(bound)
		os.rm(path) or {}
	}
	for _ in 0 .. 64 {
		mut rejected := false
		x11_connect(path, 50) or {
			rejected = true
			i32(-1)
		}
		assert rejected
	}
	assert x11_test_fd_count() == initial + 1
}

fn test_x11_connect_saturated_linux_backlog_is_bounded() {
	$if !linux {
		return
	}
	path := '/tmp/vinix-x11-backlog-${C.getpid()}.sock'
	listener := x11_test_bound_socket(path)!
	defer {
		C.close(listener)
		os.rm(path) or {}
	}
	assert C.listen(listener, 0) == 0
	mut clients := []i32{}
	defer { for fd in clients { C.close(fd) }
	 }
	mut refused := false
	started := time.sys_mono_now()
	for _ in 0 .. 64 {
		fd := x11_connect(path, 100) or {
			refused = true
			break
		}
		assert C.fcntl(fd, C.F_GETFD) & C.FD_CLOEXEC != 0
		assert C.fcntl(fd, C.F_GETFL) & C.O_NONBLOCK != 0
		clients << fd
	}
	assert refused && clients.len > 0
	assert time.sys_mono_now() - started < u64(time.second)
}

fn test_x11_exchange_has_one_deadline_and_never_blocks_on_a_silent_peer() {
	pair := control_pair()!
	defer {
		C.close(pair[0])
		C.close(pair[1])
	}
	started := time.sys_mono_now()
	mut rejected := false
	x11_exchange(pair[0], 'request'.bytes()) or {
		rejected = true
		[]u8{}
	}
	elapsed := time.sys_mono_now() - started
	assert rejected && elapsed >= u64(200 * time.millisecond)
	assert elapsed < u64(2 * time.second)
}

fn test_x11_exchange_accepts_exact_header_and_rejects_eof_and_bad_requests() {
	pair := control_pair()!
	defer {
		C.close(pair[0])
		C.close(pair[1])
	}
	header := [u8(1), 0, 11, 0, 0, 0, 0, 0]
	assert C.write(pair[1], header.data, usize(header.len)) == header.len
	assert x11_exchange(pair[0], 'request'.bytes())! == header
	for request in [[]u8{}, []u8{len: 4097}] {
		mut rejected := false
		x11_exchange(pair[0], request) or {
			rejected = true
			[]u8{}
		}
		assert rejected
	}
	closed := control_pair()!
	C.close(closed[1])
	defer { C.close(closed[0]) }
	mut rejected := false
	x11_exchange(closed[0], 'request'.bytes()) or {
		rejected = true
		[]u8{}
	}
	assert rejected
}

fn test_x11_exchange_byte_dribbling_cannot_reset_the_deadline() {
	pair := control_pair()!
	defer {
		C.close(pair[0])
		C.close(pair[1])
	}
	child := C.fork()
	assert child >= 0
	if child == 0 {
		C.close(pair[0])
		for _ in 0 .. 8 {
			C.write(pair[1], c'x', 1)
			time.sleep(80 * time.millisecond)
		}
		C._exit(0)
	}
	defer {
		C.kill(child, C.SIGKILL)
		mut status := i32(0)
		C.waitpid(child, &status, 0)
	}
	started := time.sys_mono_now()
	mut rejected := false
	x11_exchange(pair[0], 'request'.bytes()) or {
		rejected = true
		[]u8{}
	}
	assert rejected
	assert time.sys_mono_now() - started < u64(500 * time.millisecond)
}
