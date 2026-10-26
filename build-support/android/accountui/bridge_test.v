// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time
import desktop.windowfb

fn C.socketpair(i32, i32, i32, &i32) i32
fn C.pipe(&i32) i32

fn fixture_path(name string) string {
	return os.join_path(os.temp_dir(), 'vinix-account-ui-${os.getpid()}-${name}')
}

fn socket_pair() [2]i32 {
	mut pair := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0]) == 0
	return pair
}

fn pipe_pair() [2]i32 {
	mut pair := [2]i32{}
	assert C.pipe(&pair[0]) == 0
	return pair
}

fn receive_message(mut c windowfb.Connection) !windowfb.Message {
	deadline := time.sys_mono_now() + time.second
	mut m := windowfb.Message{}
	for !c.receive(&m)! {
		if time.sys_mono_now() >= deadline { return error('fixture window message timeout') }
		c.wait(10)!
	}
	return m
}

fn receive_bytes(fd int, length int) []u8 {
	mut bytes := []u8{len: length}
	mut used := 0
	deadline := time.sys_mono_now() + time.second
	for used < length {
		mut p := BridgePoll{ fd: i32(fd), events: i16(C.POLLIN) }
		assert unsafe { C.poll(&C.pollfd(&p), 1, 10) } >= 0
		assert time.sys_mono_now() < deadline
		if p.revents & C.POLLIN == 0 { continue }
		n := unsafe { C.read(fd, &bytes[used], usize(length - used)) }
		assert n > 0
		used += int(n)
	}
	return bytes
}

fn test_options_require_distinct_canonical_inherited_descriptors() {
	valid := ['--surface-fd', '3', '--input-fd', '4', '--lifetime-fd', '5']
	parsed := options(valid)!
	assert parsed.surface == 3 && parsed.input == 4 && parsed.lifetime == 5
	for text in ['-1', '0', '2', '+3', '03', '3x', '999999999999999999999'] {
		mut rejected := false
		descriptor(text) or { rejected = true }
		assert rejected
	}
	for args in [valid[..5], ['--surface-fd', '3', '--input-fd', '3', '--lifetime-fd', '5'],
		['--surface-fd', '3', '--input-fd', '4', '--lifetime-fd', '5', '--other', '/tmp/windows']] {
		mut rejected := false
		options(args) or { rejected = true }
		assert rejected
	}
}

fn test_lifetime_authority_and_eof_are_kernel_descriptors() {
	pair := socket_pair()
	defer {
		C.close(pair[0])
		C.close(pair[1])
	}
	assert lifetime_alive(int(pair[0]))!
	send_ready(int(pair[0]))!
	assert receive_bytes(int(pair[1]), 1) == [u8(1)]
	if os.getuid() == 0 {
		authorize_lifetime(int(pair[0]))!
	} else {
		mut rejected := false
		authorize_lifetime(int(pair[0])) or { rejected = true }
		assert rejected
	}
	assert C.send(pair[1], c'x', 1, 0) == 1
	mut rejected := false
	lifetime_alive(int(pair[0])) or { rejected = true }
	assert rejected
	mut byte := u8(0)
	assert C.recv(pair[0], &byte, 1, 0) == 1
	assert C.shutdown(pair[1], C.SHUT_WR) == 0
	assert !lifetime_alive(int(pair[0]))!
	pipes := pipe_pair()
	defer {
		C.close(pipes[0])
		C.close(pipes[1])
	}
	rejected = false
	authorize_lifetime(int(pipes[0])) or { rejected = true }
	assert rejected
}

fn test_window_setup_deadline_and_expired_request_are_bounded() {
	pair := socket_pair()
	lifetime := socket_pair()
	defer {
		C.close(pair[1])
		C.close(lifetime[0])
		C.close(lifetime[1])
	}
	mut c := windowfb.adopt(int(pair[0]))!
	defer {
		c.close()
		unsafe { free(c) }
	}
	mut rejected := false
	create_window_before(c, 64, 64, int(lifetime[0]), time.sys_mono_now() - 1) or {
		rejected = true
	}
	assert rejected
	assert C.shutdown(lifetime[1], C.SHUT_WR) == 0
	rejected = false
	connect_window('/tmp/missing-account-ui-window', int(lifetime[0]), time.sys_mono_now() + time.second) or {
		assert err.msg().contains('expired')
		rejected = true
	}
	assert rejected
}

fn test_unix_window_connect_checks_peer_and_bounds_a_full_backlog() {
	path := fixture_path('windows')
	address := window_address(path)!
	listener := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	assert listener >= 0
	defer {
		C.close(listener)
		os.rm(path) or {}
	}
	assert C.bind(listener, unsafe { voidptr(&address) }, u32(sizeof(WindowAddress))) == 0
	assert C.listen(listener, 1) == 0
	lifetime := socket_pair()
	defer {
		C.close(lifetime[0])
		C.close(lifetime[1])
	}
	mut c := connect_window(path, int(lifetime[0]), time.sys_mono_now() + time.second)!
	c.close()
	unsafe { free(c) }
	accepted := C.accept(listener, unsafe { nil }, unsafe { nil })
	assert accepted >= 0
	C.close(accepted)
	mut pending := []int{}
	defer {
		for fd in pending { C.close(fd) }
	}
	for _ in 0 .. 64 {
		fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
		assert fd >= 0
		pending << int(fd)
		protect_fd(int(fd), true)!
		_ = C.connect(fd, unsafe { voidptr(&address) }, u32(sizeof(WindowAddress)))
	}
	start := time.sys_mono_now()
	mut rejected := false
	mut extra := connect_window(path, int(lifetime[0]), start + 32 * time.millisecond) or {
		rejected = true
		unsafe { nil }
	}
	if extra != unsafe { nil } {
		extra.close()
		unsafe { free(extra) }
	}
	assert rejected
	assert time.sys_mono_now() - start < 500 * time.millisecond
}

fn test_source_claim_copy_layout_cache_and_malformed_source() {
	path := fixture_path('source')
	destination_path := fixture_path('destination')
	defer {
		os.rm(path) or {}
		os.rm(destination_path) or {}
	}
	mut producer := windowfb.create_surface(path, 64, 64)!
	defer { producer.close() }
	fd := C.open(&char(path.str), C.O_RDWR | C.O_CLOEXEC)
	assert fd >= 0
	defer { C.close(fd) }
	mut source := open_source(fd)!
	defer { source.close() }
	p := unsafe { &u8(source.mapping) }
	mut destination := windowfb.create_surface(destination_path, 64, 64)!
	defer { destination.close() }
	unsafe {
		producer.back[0] = 0xff123456
		producer.back[4095] = 0xffabcdef
	}
	C.atomic_store_u32(unsafe { p + 28 }, 1)
	assert source.copy_to(&destination)!
	assert unsafe { destination.back[0] } == 0xff123456
	assert unsafe { destination.back[4095] } == 0xffabcdef
	assert C.atomic_load_u32(unsafe { p + 32 }) == no_reader
	// A publisher's later geometry mutation must not influence the cached
	// offsets or output dimensions. Invalid active indices still fail closed.
	windowfb.put_u32(p, 12, ~u32(0))
	windowfb.put_u32(p, 40, ~u32(0))
	assert source.copy_to(&destination)!
	assert unsafe { destination.back[4095] } == 0xffabcdef
	C.atomic_store_u32(unsafe { p + 28 }, 2)
	mut rejected := false
	source.copy_to(&destination) or { rejected = true }
	assert rejected
	C.atomic_store_u32(unsafe { p + 28 }, 0)
	windowfb.put_u32(p, 12, 64)
	windowfb.put_u32(p, 40, 64 * 64 * 4)
	for offset in [0, 4, 8, 12, 16, 20, 24, 40] {
		original := windowfb.take_u32(p, offset)
		windowfb.put_u32(p, offset, ~u32(0))
		rejected = false
		mut invalid := open_source(fd) or {
			rejected = true
			Source{}
		}
		invalid.close()
		assert rejected
		windowfb.put_u32(p, offset, original)
	}
	C.atomic_store_u32(unsafe { p + 32 }, 0)
	rejected = false
	open_source(fd) or { rejected = true }
	assert rejected
	C.atomic_store_u32(unsafe { p + 32 }, no_reader)
	ro := C.open(&char(path.str), C.O_RDONLY | C.O_CLOEXEC)
	assert ro >= 0
	defer { C.close(ro) }
	rejected = false
	open_source(ro) or { rejected = true }
	assert rejected
	assert C.ftruncate(fd, i64(source_header + 64 * 64 * 4)) == 0
	rejected = false
	open_source(fd) or { rejected = true }
	assert rejected
}

fn test_input_wire_order_binary_keys_bounds_and_queue_retirement() {
	pipes := pipe_pair()
	defer {
		C.close(pipes[0])
		C.close(pipes[1])
	}
	prepare_input(int(pipes[1]))!
	mut rejected := false
	prepare_input(int(pipes[0])) or { rejected = true }
	assert rejected
	mut queue := InputQueue{}
	motion := windowfb.message(.motion, -10, 100, 0, '')!
	mut keys := windowfb.message(.keys, 4, 5, 0, 'x\x00\xe2\x82\xac')!
	down := windowfb.message(.button_down, 3, 4, 1, '')!
	up := windowfb.message(.button_up, 3, 4, 1, '')!
	for event in [motion, keys, down, up] { queue.enqueue(&event, 64, 64)! }
	queue.flush(int(pipes[1]))!
	assert !queue.pending()
	wire := receive_bytes(int(pipes[0]), 4 * input_header + keys.length)
	assert windowfb.take_u32(wire.data, 0) == input_magic
	assert windowfb.take_u32(wire.data, 4) == 1
	assert windowfb.take_u32(wire.data, 8) == 0
	assert windowfb.take_u32(wire.data, 12) == 63
	assert windowfb.take_u32(wire.data, 28) == 4
	assert windowfb.take_u32(wire.data, 44) == u32(keys.length)
	assert wire[48..48 + keys.length] == keys.payload[..keys.length]
	assert windowfb.take_u32(wire.data, 48 + keys.length + 4) == 2
	assert windowfb.take_u32(wire.data, 72 + keys.length + 4) == 3
	for record in queue.records {
		for byte in record.payload {
			assert byte == 0
		}
	}
	keys.length = windowfb.max_payload + 1
	rejected = false
	queue.enqueue(&keys, 64, 64) or { rejected = true }
	assert rejected
	for _ in 0 .. input_limit { queue.enqueue(&up, 64, 64)! }
	rejected = false
	queue.enqueue(&up, 64, 64) or { rejected = true }
	assert rejected
}

fn test_input_backpressure_retries_without_duplicate_or_reordered_headers() {
	pipes := pipe_pair()
	defer {
		C.close(pipes[0])
		C.close(pipes[1])
	}
	prepare_input(int(pipes[1]))!
	// Fill a real nonblocking pipe. No service read may make progress yet.
	padding := [512]u8{}
	mut filled := 0
	for {
		n := C.write(pipes[1], &padding[0], padding.len)
		if n < 0 {
			assert C.errno in [C.EAGAIN, C.EWOULDBLOCK]!
			break
		}
		assert n == padding.len
		filled += int(n)
	}
	assert filled > 0
	mut queue := InputQueue{}
	keys := windowfb.message(.keys, 0, 0, 0, 'q'.repeat(windowfb.max_payload))!
	up := windowfb.message(.button_up, 2, 3, 1, '')!
	queue.enqueue(&keys, 64, 64)!
	queue.enqueue(&up, 64, 64)!
	queue.flush(int(pipes[1]))!
	assert queue.count == 2 && !queue.records[queue.head].header_sent
	// Linux needs a complete PIPE_BUF slot freed before another atomic
	// header can be queued; macOS can make progress after its smaller slot.
	released := int(C.fpathconf(pipes[1], C._PC_PIPE_BUF))
	assert released >= input_header && released <= filled
	_ = receive_bytes(int(pipes[0]), released)
	queue.flush(int(pipes[1]))!
	assert queue.count == 2 && queue.records[queue.head].header_sent
	_ = receive_bytes(int(pipes[0]), filled - released)
	queue.flush(int(pipes[1]))!
	wire := receive_bytes(int(pipes[0]), input_header + keys.length + input_header)
	assert windowfb.take_u32(wire.data, 4) == 4
	assert windowfb.take_u32(wire.data, 20) == u32(windowfb.max_payload)
	assert wire[24..24 + keys.length] == keys.payload[..keys.length]
	assert windowfb.take_u32(wire.data, 24 + keys.length + 4) == 3
	assert !queue.pending()
}

fn test_complete_create_present_ack_input_and_close_over_real_stream() {
	source_path := fixture_path('bridge-source')
	desktop_path := fixture_path('bridge-desktop')
	defer {
		os.rm(source_path) or {}
		os.rm(desktop_path) or {}
	}
	mut producer := windowfb.create_surface(source_path, 64, 64)!
	defer { producer.close() }
	mut desktop := windowfb.create_surface(desktop_path, 64, 64)!
	defer { desktop.close() }
	fd := C.open(&char(source_path.str), C.O_RDWR | C.O_CLOEXEC)
	assert fd >= 0
	mut source := open_source(fd)!
	C.close(fd)
	defer { source.close() }
	unsafe { producer.back[0] = 0xff102030 }
	C.atomic_store_u32(unsafe { &u8(source.mapping) + 28 }, 1)
	pipes := pipe_pair()
	defer {
		C.close(pipes[0])
		C.close(pipes[1])
	}
	prepare_input(int(pipes[1]))!
	lifetime := socket_pair()
	defer {
		C.close(lifetime[0])
		C.close(lifetime[1])
	}
	pair := socket_pair()
	mut client := windowfb.adopt(int(pair[0]))!
	mut server := windowfb.adopt(int(pair[1]))!
	defer {
		server.close()
		unsafe { free(server) }
	}
	// Send CREATED before create_window to keep this deterministic without
	// threads, then inspect the actual CREATE bytes from the peer afterward.
	created := windowfb.message(.created, 64, 64, 256, desktop_path)!
	server.send(&created)!
	mut window := create_window(client, 64, 64, int(lifetime[0]))!
	defer { window.close() }
	request := receive_message(mut server)!
	assert request.kind == .create && request.value == 0 && request.x == 64 && request.y == 64
	assert request.text() == 'Google account'
	mut queue := InputQueue{}
	assert bridge_tick(mut window, &source, mut queue, int(pipes[1]))!
	assert window.frame_pending
	present := receive_message(mut server)!
	assert present.kind == .present && present.value == 0
	assert unsafe { desktop.back[0] } == 0xff102030
	// Do not overwrite the pending compositor buffer before FRAME_DONE.
	unsafe { producer.back[0] = 0xff405060 }
	assert bridge_tick(mut window, &source, mut queue, int(pipes[1]))!
	assert unsafe { desktop.back[0] } == 0xff102030
	ack := windowfb.message(.frame_done, 0, 0, 0, '')!
	server.send(&ack)!
	keys := windowfb.message(.keys, 0, 0, 0, 'abc')!
	server.send(&keys)!
	assert bridge_tick(mut window, &source, mut queue, int(pipes[1]))!
	assert unsafe { desktop.back[0] } == 0xff405060
	_ = receive_message(mut server)!
	wire := receive_bytes(int(pipes[0]), input_header + keys.length)
	assert windowfb.take_u32(wire.data, 4) == 4 && wire[24..] == 'abc'.bytes()
	close := windowfb.message(.close, 0, 0, 0, '')!
	server.send(&close)!
	assert !bridge_tick(mut window, &source, mut queue, int(pipes[1]))!
}
