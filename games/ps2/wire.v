// SPDX-License-Identifier: GPL-2.0-or-later
// VAPP v10 uses the same element layout as the existing iOS/native clients.
module main

import math.bits

fn wire_io(fd int, pointer voidptr, size int, writing bool) bool {
	mut offset := 0
	for offset < size {
		address := unsafe { voidptr(usize(pointer) + usize(offset)) }
		count := if writing {
			C.write(fd, address, usize(size - offset))
		} else {
			C.read(fd, address, usize(size - offset))
		}
		if count < 0 && C.errno == C.EINTR { continue }
		if count <= 0 { return false }
		offset += int(count)
	}
	return true
}

fn wire_u32(mut bytes []u8, value u32) {
	for shift := 0; shift < 32; shift += 8 { bytes << u8(value >> shift) }
}

fn wire_f64(mut bytes []u8, value f64) {
	value_bits := bits.f64_bits(value)
	wire_u32(mut bytes, u32(value_bits))
	wire_u32(mut bytes, u32(value_bits >> 32))
}

fn wire_string(mut bytes []u8, text string) {
	wire_u32(mut bytes, u32(text.len))
	unsafe { bytes.push_many(text.str, text.len) }
}

fn wire_number(bytes []u8, offset int) u32 {
	return u32(bytes[offset]) | u32(bytes[offset + 1]) << 8 | u32(bytes[offset + 2]) << 16 | u32(bytes[offset + 3]) << 24
}

fn encode_element(mut bytes []u8, kind u8, x f64, y f64, width f64, height f64,
	id string, text string, image string, children int) {
	bytes << kind
	bytes << u8(64 | if kind == 4 {
		8
	} else if kind == 2 {
		1
	} else {
		0
	})
	bytes << u8(1) // centered text
	for _ in 0 .. 3 { bytes << u8(0) }
	wire_u32(mut bytes, 0)
	for value in [x, y, width, height]! { wire_f64(mut bytes, value) }
	wire_u32(mut bytes, if kind == 4 { u32(0x344156) } else { u32(0x141b28) })
	wire_f64(mut bytes, if kind == 4 { f64(5) } else { f64(0) })
	wire_u32(mut bytes, 0)
	for _ in 0 .. 4 { wire_f64(mut bytes, 0) }
	wire_u32(mut bytes, 0xf5f7fa)
	wire_u32(mut bytes, 0)
	wire_f64(mut bytes, 14)
	for _ in 0 .. 3 { wire_f64(mut bytes, 0) }
	wire_u32(mut bytes, 1)
	for _ in 0 .. 3 { wire_u32(mut bytes, 0) }
	for _ in 0 .. 6 { wire_f64(mut bytes, 0) }
	for _ in 0 .. 3 { wire_u32(mut bytes, 0) }
	for _ in 0 .. 2 { wire_f64(mut bytes, 0) }
	for _ in 0 .. 6 { wire_u32(mut bytes, 0) }
	wire_f64(mut bytes, 0)
	for _ in 0 .. 3 { wire_u32(mut bytes, 0) }
	wire_f64(mut bytes, 0)
	wire_string(mut bytes, id)
	wire_string(mut bytes, id)
	wire_string(mut bytes, '')
	wire_string(mut bytes, text)
	wire_string(mut bytes, image)
	for _ in 0 .. 5 { wire_string(mut bytes, '') }
	wire_string(mut bytes, 'middle')
	wire_string(mut bytes, '')
	wire_u32(mut bytes, 0)
	wire_u32(mut bytes, u32(children))
}

fn ui_reply(fd int, state []u8, payload []u8) bool {
	mut header := []u8{cap: 128}
	defer { unsafe { header.free() } }
	wire_u32(mut header, 0x56415050)
	header << u8(10)
	for _ in 0 .. 3 { header << u8(0) }
	header << state
	wire_u32(mut header, u32(payload.len))
	return header.len == 128 && wire_io(fd, header.data, header.len, true)
		&& (payload.len == 0 || wire_io(fd, payload.data, payload.len, true))
}
