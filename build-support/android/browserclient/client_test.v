// SPDX-License-Identifier: GPL-2.0-or-later
module browserclient

import browseripc
import encoding.binary

fn C.socketpair(i32, i32, i32, &i32) i32
fn C.pipe(&i32) i32

fn pair() [2]i32 {
	mut sockets := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) == 0
	return sockets
}

fn wire(op browseripc.Op, request u64, view u64, generation u64, navigation u64,
	payload []u8) []u8 {
	mut bytes := browseripc.encode_header(browseripc.Header{
		op:           op
		request:      request
		view:         view
		generation:   generation
		navigation:   navigation
		payload_size: u32(payload.len)
	},
		.engine_to_client) or { panic(err) }
	bytes << payload
	return bytes
}

fn send_bytes(fd i32, bytes []u8) {
	assert C.send(fd, bytes.data, usize(bytes.len), 0) == bytes.len
}

fn test_fragmented_header_and_cookie_completion_order() {
	sockets := pair()
	mut c := open(sockets[0]) or { panic(err) }
	defer {
		c.close()
		C.close(sockets[1])
	}
	size := [u8(8), 0, 0, 0, 8, 0, 0, 0]
	assert c.submit(.create, 1, 1, 0, size) or { panic(err) } == 1
	get := [u8(1), 0, 0, 0, `x`]
	assert c.submit(.cookie_get, 0, 0, 0, get) or { panic(err) } == 2
	ack := wire(.ack, 1, 1, 1, 0, []u8{})
	send_bytes(sockets[1], ack[..17])
	assert !(c.read(0, 0) or { panic(err) }).available
	assert c.header_used == 17
	assert c.payload.len == 0
	send_bytes(sockets[1], ack[17..])
	cookies := 'token=opaque'.bytes()
	send_bytes(sockets[1], wire(.cookie_result, 2, 0, 0, 0, cookies))
	result := c.read(2, 500) or { panic(err) }
	assert result.available && result.payload == cookies
	unsafe { result.payload.free() }
	first := c.read(0, 0) or { panic(err) }
	assert first.available && first.header.op == .ack && first.header.request == 1
	unsafe { first.payload.free() }
	assert !(c.read(0, 0) or { panic(err) }).available
}

fn test_eof_protocol_failure_and_completion_timeout_close_channel() {
	for scenario in 0 .. 3 {
		sockets := pair()
		mut c := open(sockets[0]) or { panic(err) }
		get := [u8(1), 0, 0, 0, `x`]
		request := c.submit(.cookie_get, 0, 0, 0, get) or { panic(err) }
		if scenario == 0 { C.close(sockets[1]) }
		if scenario == 1 {
			mut bad := wire(.cookie_result, request, 0, 0, 0, []u8{})
			bad[44] = 1
			send_bytes(sockets[1], bad)
		}
		mut rejected := false
		c.read(request, 1) or {
			rejected = true
			Event{}
		}
		assert rejected && c.closed && c.fd == -1
		assert c.payload.len == 0 && c.queue.len == 0
		c.close()
		if scenario != 0 { C.close(sockets[1]) }
	}
}

fn test_non_socket_and_unknown_abi_operation_rejected() {
	mut pipes := [2]i32{}
	assert C.pipe(&pipes[0]) == 0
	mut rejected := false
	open(pipes[0]) or {
		rejected = true
		unsafe { &Client(nil) }
	}
	assert rejected
	C.close(pipes[0])
	C.close(pipes[1])
	sockets := pair()
	mut c := open(sockets[0]) or { panic(err) }
	defer {
		c.close()
		C.close(sockets[1])
	}
	assert abi_submit(c, 255, 1, 1, 1, unsafe { nil }, 0) == 0
	assert !c.closed
}

fn test_policy_id_cannot_complete_cookie_request() {
	sockets := pair()
	mut c := open(sockets[0]) or { panic(err) }
	defer {
		c.close()
		C.close(sockets[1])
	}
	size := [u8(8), 0, 0, 0, 8, 0, 0, 0]
	assert (c.submit(.create, 1, 1, 0, size) or { panic(err) }) == 1
	assert (c.submit(.navigate, 1, 1, 1, 'https://example.test/'.bytes()) or { panic(err) }) == 2
	get := [u8(1), 0, 0, 0, `x`]
	assert (c.submit(.cookie_get, 0, 0, 0, get) or { panic(err) }) == 3
	mut policy := []u8{len: 8}
	binary.little_endian_put_u64(mut policy, 3)
	policy << 'https://example.test/next'.bytes()
	send_bytes(sockets[1], wire(.policy_request, 3, 1, 1, 1, policy))
	send_bytes(sockets[1], wire(.cookie_result, 3, 0, 0, 0, 'a=b'.bytes()))
	result := c.read(3, 500) or { panic(err) }
	assert result.header.op == .cookie_result && result.payload == 'a=b'.bytes()
	unsafe { result.payload.free() }
	callback := c.read(0, 0) or { panic(err) }
	assert callback.header.op == .policy_request && callback.payload == policy
	unsafe { callback.payload.free() }
}

fn test_public_abi_roundtrip_and_descriptor_ownership() {
	sockets := pair()
	handle := abi_open(sockets[0])
	assert handle != unsafe { nil }
	defer { C.close(sockets[1]) }
	get := [u8(1), 0, 0, 0, `x`]
	request := abi_submit(handle, u16(browseripc.Op.cookie_get), 0, 0, 0, get.data, u32(get.len))
	assert request == 1
	expected := 'session=opaque'.bytes()
	send_bytes(sockets[1], wire(.cookie_result, request, 0, 0, 0, expected))
	mut header := []u8{len: browseripc.header_size}
	mut payload := unsafe { &u8(nil) }
	mut length := u32(0)
	assert abi_read(handle, request, header.data, &payload, &length, 500) == 1
	decoded := browseripc.decode_header(header, .engine_to_client) or { panic(err) }
	assert decoded.op == .cookie_result && decoded.request == request
	assert length == expected.len
	assert unsafe { payload.vbytes(int(length)) } == expected
	assert abi_read(handle, 0, header.data, &payload, &length, 0) == 0
	abi_close(handle)
	assert C.fcntl(sockets[0], C.F_GETFD) == -1
	abi_close(unsafe { nil })
}
