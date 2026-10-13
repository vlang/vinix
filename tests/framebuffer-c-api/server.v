// SPDX-License-Identifier: MIT
module main

import desktop.windowfb
import os
import time

fn send_split(mut peer windowfb.Connection, m &windowfb.Message) ! {
	mut bytes := [windowfb.header_size + windowfb.max_payload]u8{}
	windowfb.put_u32(&bytes[0], 0, windowfb.magic)
	windowfb.put_u32(&bytes[0], 4, u32(m.kind))
	windowfb.put_u32(&bytes[0], 8, u32(m.x))
	windowfb.put_u32(&bytes[0], 12, u32(m.y))
	windowfb.put_u32(&bytes[0], 16, u32(m.value))
	windowfb.put_u32(&bytes[0], 20, u32(m.length))
	for i in 0 .. m.length { bytes[windowfb.header_size + i] = m.payload[i] }
	for i in 0 .. windowfb.header_size + m.length {
		if unsafe { C.write(peer.fd, &bytes[i], 1) } != 1 {
			return error('cannot send fragmented event')
		}
		time.sleep(time.millisecond)
	}
}

fn main() {
	path := os.args[1]
	mut listener := windowfb.listen(path)!
	defer { listener.close() }
	mut peer := &windowfb.Connection(unsafe { nil })
	for peer == unsafe { nil } {
		if connected := listener.accept() { peer = connected }
		time.sleep(time.millisecond)
	}
	defer {
		peer.close()
		unsafe { free(peer) }
	}
	mut request := windowfb.Message{}
	for !peer.receive(unsafe { &request })! { peer.wait(5000)! }
	assert request.kind == .create && request.x == 128 && request.y == 96
	file := path + '.pixels'
	mut surface := windowfb.create_surface(file, 128, 96)!
	defer {
		surface.close()
		os.rm(file) or {}
	}
	reply := windowfb.message(.created, 128, 96, 512, file)!
	send_split(mut peer, unsafe { &reply })!
	for !peer.receive(unsafe { &request })! { peer.wait(5000)! }
	assert request.kind == .present
	assert unsafe { surface.back[0] } == 0x123456
	assert unsafe { surface.back[128 * 96 - 1] } == 0xabcdef
	surface.copy_frame()
	for m in [
		windowfb.message(.frame_done, 0, 0, 0, '')!,
		windowfb.message(.motion, -12, 34, 3, '')!,
		windowfb.message(.keys, 0, 0, 0, 'a\x00b')!,
	] {
		send_split(mut peer, unsafe { &m })!
	}
	for {
		peer.receive(unsafe { &request }) or {
			unsafe { err.free() }
			break
		}
		peer.wait(5000)!
	}
}
