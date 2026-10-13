// SPDX-License-Identifier: MIT
// Toolkit-independent Vinix window protocol. All integers are little endian.
module windowfb

pub const magic = u32(0x31465756) // VWF1
pub const header_size = 24
pub const max_payload = 4096
pub const max_clients = 32
// CREATE.value feature bits. Zero retains the original fixed-buffer protocol.
pub const resize_buffers = 1
pub const kitty_keyboard = 2
pub const client_features = resize_buffers | kitty_keyboard

pub enum Kind as u32 {
	create = 1
	created
	present
	frame_done
	motion
	button_down
	button_up
	keys
	wheel
	horizontal_wheel
	configure
	focus
	close
	set_title
	buffer_ack
}

pub struct Message {
pub mut:
	kind    Kind = .close
	x       i32
	y       i32
	value   i32
	length  int
	payload [max_payload]u8
}

pub fn message(kind Kind, x int, y int, value int, text string) !Message {
	if text.len > max_payload { return error('window message is too large') }
	mut m := Message{ kind: kind, x: i32(x), y: i32(y), value: i32(value), length: text.len }
	for i, byte in text { m.payload[i] = byte }
	return m
}

// Borrowed until this Message is overwritten. Clone to retain it.
pub fn (m &Message) text() string {
	return unsafe { tos(&m.payload[0], m.length) }
}

pub fn put_u32(bytes &u8, offset int, value u32) {
	unsafe {
		for i in 0 .. 4 { bytes[offset + i] = u8(value >> (i * 8)) }
	}
}

pub fn take_u32(bytes &u8, offset int) u32 {
	return unsafe { u32(bytes[offset]) | u32(bytes[offset + 1]) << 8 | u32(bytes[offset + 2]) << 16 | u32(bytes[offset + 3]) << 24 }
}

fn decode_header(bytes &u8) !Message {
	if take_u32(bytes, 0) != magic { return error('invalid window protocol magic') }
	kind := take_u32(bytes, 4)
	length := take_u32(bytes, 20)
	if kind < u32(Kind.create) || kind > u32(Kind.buffer_ack) || length > max_payload {
		return error('invalid window message header')
	}
	return Message{
		kind:   unsafe { Kind(kind) }
		x:      i32(take_u32(bytes, 8))
		y:      i32(take_u32(bytes, 12))
		value:  i32(take_u32(bytes, 16))
		length: int(length)
	}
}
