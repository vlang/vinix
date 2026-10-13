// SPDX-License-Identifier: MIT
module windowfb

import os

fn C.socketpair(i32, i32, i32, &i32) i32

fn invalid_header(bytes &u8) bool {
	decode_header(bytes) or {
		unsafe { err.free() }
		return true
	}
	return false
}

fn test_fragmented_messages_and_waitable_fd() {
	mut pair := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0]) == 0
	mut receiver := adopt(int(pair[0]))!
	mut sender := adopt(int(pair[1]))!
	defer {
		receiver.close()
		sender.close()
		unsafe {
			free(receiver)
			free(sender)
		}
	}
	mut bytes := [header_size + 3]u8{}
	put_u32(&bytes[0], 0, magic)
	put_u32(&bytes[0], 4, u32(Kind.keys))
	put_u32(&bytes[0], 8, u32(i32(-12)))
	put_u32(&bytes[0], 20, 3)
	bytes[24] = `a`
	bytes[25] = `b`
	bytes[26] = `c`
	mut received := Message{}
	assert !receiver.wait(0)!
	for i in 0 .. bytes.len {
		assert unsafe { C.send(sender.fd, &bytes[i], 1, 0) } == 1
		assert receiver.wait(100)!
		ready := receiver.receive(unsafe { &received })!
		assert ready == (i == bytes.len - 1)
	}
	assert received.kind == .keys && received.x == -12 && received.text() == 'abc'
	for kind in [Kind.motion, .configure, .frame_done, .close] {
		m := message(kind, 4, 5, -1, '')!
		sender.send(unsafe { &m })!
	}
	for kind in [Kind.motion, .configure, .frame_done, .close] {
		assert receiver.receive(unsafe { &received })!
		assert received.kind == kind && received.value == -1 && received.length == 0
	}
	assert !receiver.receive(unsafe { &received })!
	sender.close()
	assert receiver.wait(100)!
	receiver.receive(unsafe { &received }) or {
		assert err.msg().contains('disconnected')
		return
	}
	assert false
}

fn test_invalid_header_and_bounded_output() {
	mut bytes := [header_size]u8{}
	assert invalid_header(unsafe { &bytes[0] })
	put_u32(&bytes[0], 0, magic)
	put_u32(&bytes[0], 4, 999)
	assert invalid_header(unsafe { &bytes[0] })
	put_u32(&bytes[0], 4, u32(Kind.keys))
	put_u32(&bytes[0], 20, max_payload + 1)
	assert invalid_header(unsafe { &bytes[0] })
	mut pair := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0]) == 0
	mut c := adopt(int(pair[0]))!
	defer {
		c.close()
		C.close(pair[1])
		unsafe { free(c) }
	}
	m := message(.keys, 0, 0, 0, 'x'.repeat(max_payload))!
	mut rejected := false
	for _ in 0 .. 10000 {
		c.send(unsafe { &m }) or {
			rejected = true
			break
		}
	}
	assert rejected
	assert c.queued <= c.tx.len
}

fn test_shared_framebuffer_copy_and_retirement() {
	path := os.join_path(os.temp_dir(), 'vinix-windowfb-${os.getpid()}')
	defer {
		os.rm(path) or {}
		unsafe { path.free() }
	}
	mut producer := create_surface(path, 64, 64)!
	defer { producer.close() }
	mut client := open_surface(path, 64, 64)!
	defer { client.close() }
	unsafe {
		client.back[0] = 0x123456
		client.back[4095] = 0xabcdef
	}
	front := unsafe { &u32(usize(producer.mapping) + surface_header_size) }
	assert unsafe { front[0] } == 0
	producer.copy_frame()
	assert unsafe { front[0] } == 0x123456
	assert unsafe { front[4095] } == 0xabcdef
	unsafe { client.back[0] = 0xff00ff }
	assert unsafe { front[0] } == 0x123456
	producer.copy_frame()
	assert unsafe { front[0] } == 0xff00ff
	assert take_u32(producer.mapping, 28) == 0
	assert take_u32(producer.mapping, 32) == ~u32(0)
	client.close()
	client.close()
	producer.close()
	producer.close()
	surface_size(8192, 8192) or {
		assert err.msg().contains('large')
		return
	}
	assert false
}
