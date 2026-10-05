// SPDX-License-Identifier: GPL-2.0-or-later
// UIKit views cross the same VAPP v10 boundary as standalone Vinix apps.
module main

import math
import math.bits

#include <unistd.h>
#include <errno.h>

fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize

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
	v := bits.f64_bits(value)
	wire_u32(mut bytes, u32(v))
	wire_u32(mut bytes, u32(v >> 32))
}

fn wire_string(mut bytes []u8, text string) {
	wire_u32(mut bytes, u32(text.len))
	unsafe { bytes.push_many(text.str, text.len) }
}

fn wire_number(bytes []u8, offset int) u32 {
	return u32(bytes[offset]) | u32(bytes[offset + 1]) << 8 | u32(bytes[offset + 2]) << 16 | u32(bytes[offset + 3]) << 24
}

fn wire_color(object u64, fallback u32) u32 {
	return if object == 0 { fallback } else { obj_header(object).color }
}

fn encode_view(mut bytes []u8, object u64, index int, root bool, depth int) ! {
	if depth > 32 || bytes.len > 1024 * 1024 {
		return error('UIKit view tree exceeds protocol limits')
	}
	header := obj_header(object)
	button := header.target != 0
	label := if button { obj_header(header.fields[5]) } else { header }
	text := if label.fields[0] != 0 { ctext(u64(obj_header(label.fields[0]).text)) } else { '' }
	font := if label.fields[1] == 0 { f64(17) } else { obj_header(label.fields[1]).font_size }
	kind := if root {
		u8(0)
	} else if button {
		u8(4)
	} else if label.fields[0] != 0 {
		u8(2)
	} else {
		u8(1)
	}
	bytes << kind
	bytes << u8(64 | if button {
		8
	} else if kind == 2 {
		1
	} else {
		0
	})
	bytes << u8(if button { 1 } else { label.align })
	bytes << u8(0)
	bytes << u8(0)
	bytes << u8(0)
	wire_u32(mut bytes, 0)
	for value in [header.frame.x, header.frame.y, header.frame.width, header.frame.height]! {
		wire_f64(mut bytes, value)
	}
	wire_u32(mut bytes, wire_color(header.fields[2], 0))
	wire_f64(mut bytes, if header.fields[4] == 0 {
		f64(0)
	} else {
		obj_header(header.fields[4]).radius
	})
	wire_u32(mut bytes, 0)
	for _ in 0 .. 4 { wire_f64(mut bytes, 0) }
	wire_u32(mut bytes, wire_color(label.fields[3], 0xffffff))
	wire_u32(mut bytes, 0)
	// UILabel's fit-to-width subset. The compositor supplies actual glyphs.
	wire_f64(mut bytes, math.min(font, if text.len > 0 {
		header.frame.width / (f64(text.len) * 0.65)
	} else {
		font
	}))
	for _ in 0 .. 3 { wire_f64(mut bytes, 0) }
	wire_u32(mut bytes, 1) // text lines
	for _ in 0 .. 3 { wire_u32(mut bytes, 0) }
	for _ in 0 .. 6 { wire_f64(mut bytes, 0) }
	for _ in 0 .. 3 { wire_u32(mut bytes, 0) }
	for _ in 0 .. 2 { wire_f64(mut bytes, 0) }
	for _ in 0 .. 6 { wire_u32(mut bytes, 0) }
	wire_f64(mut bytes, 0)
	for _ in 0 .. 3 { wire_u32(mut bytes, 0) }
	wire_f64(mut bytes, 0)
	mut id_buffer := [32]u8{}
	length := if button {
		C.snprintf(unsafe { &char(&id_buffer[0]) }, 32, c'ios.%d', index)
	} else {
		0
	}
	id := unsafe { tos(&id_buffer[0], length) }
	wire_string(mut bytes, id)
	wire_string(mut bytes, id)
	wire_string(mut bytes, '')
	wire_string(mut bytes, text)
	for _ in 0 .. 6 { wire_string(mut bytes, '') }
	wire_string(mut bytes, if kind == 2 { 'bottom' } else { 'middle' })
	wire_string(mut bytes, '')
	wire_u32(mut bytes, 0) // menu
	wire_u32(mut bytes, u32(header.child_count))
	for i in 0 .. header.child_count {
		encode_view(mut bytes, header.children[i], i, false, depth + 1)!
	}
}

fn ui_reply(fd int, state []u8, payload []u8) bool {
	mut header := []u8{cap: 128}
	wire_u32(mut header, 0x56415050)
	header << u8(10)
	header << u8(0)
	header << u8(0)
	header << u8(0)
	header << state
	wire_u32(mut header, u32(payload.len))
	ok := header.len == 128 && wire_io(fd, header.data, header.len, true)
		&& (payload.len == 0 || wire_io(fd, payload.data, payload.len, true))
	unsafe { header.free() }
	return ok
}

fn ui_event_loop(request int, response int) ! {
	if request < 0 || response < 0 || request == response {
		return error('invalid desktop descriptors')
	}
	mut state := []u8{len: 116}
	state[36] = 1 // US keyboard
	state[48] = 1 // 100% scale (the protocol uses integer factors)
	mut encoded := []u8{cap: 16384}
	defer { unsafe {
		state.free()
		encoded.free()
	}
	 }
	if !ui_reply(response, state, encoded) { return error('desktop handshake failed') }
	mut header := []u8{len: 136}
	defer { unsafe { header.free() } }
	for wire_io(request, header.data, header.len, false) {
		if wire_number(header, 0) != 0x56415050 || header[4] != 10 {
			return error('unsupported desktop protocol')
		}
		length := int(wire_number(header, 132))
		if length < 0 || length > 65536 { return error('desktop payload exceeds limit') }
		mut payload := []u8{len: length}
		if length > 0 && !wire_io(request, payload.data, length, false) {
			unsafe { payload.free() }
			return error('short desktop payload')
		}
		unsafe { C.memcpy(state.data, &header[16], 116) }
		pool := objc_pool_push()
		encoded.clear()
		command := header[5]
		match command {
			1 {
				width := int(wire_number(header, 8))
				height := int(wire_number(header, 12))
				if width < 1 || height < 1 || width > 8192 || height > 8192 {
					return error('invalid UIKit window size')
				}
				ui_layout(width, height)
				encode_view(mut encoded, ui_root_view(), -1, true, 0)!
			}
			2 {
				text := unsafe { tos(payload.data, payload.len) }
				if !text.starts_with('ios.') { return error('invalid UIKit action') }
				suffix := text[4..]
				index := suffix.int()
				unsafe { suffix.free() }
				ui_action(index)!
			}
			3, 7 {
				view := obj_header(ui_root_view())
				for key in payload {
					tag := match key {
						10, 13 { i64(`=`) }
						`c`, 27 { i64(`C`) }
						else { i64(key) }
					}
					for i in 0 .. view.child_count {
						if obj_header(view.children[i]).target != 0 && obj_header(view.children[i]).tag == tag {
							ui_action(i)!
						}
					}
				}
			}
			4 { encoded << u8(0) }
			6 {}
			else { return error('unsupported UIKit desktop command') }
		}
		objc_pool_pop(pool)
		unsafe { payload.free() }
		if !ui_reply(response, state, encoded) { break }
		if command == 6 { break }
	}
}
