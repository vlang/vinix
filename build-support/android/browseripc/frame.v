// SPDX-License-Identifier: GPL-2.0-or-later
module browseripc

import encoding.binary
import encoding.utf8

// A receiver reads exactly header_size bytes, validates them, then reads exactly
// payload_size bytes. It must not allocate from an unvalidated length or log
// payloads: URI, form input and cookie messages can contain account secrets.
pub const header_size = 48
pub const max_dimension = 2048
pub const max_pixels = max_dimension * max_dimension * 4
pub const max_payload = max_pixels + 16
pub const max_text = 1024 * 1024

pub enum Op as u16 {
	create = 1
	resize
	navigate
	javascript
	pointer
	key
	text
	scroll
	destroy
	cookie_set
	cookie_get
	cookie_delete
	policy_reply
	ack    = 256
	pixels
	navigation
	failure
	cookie_result
	policy_request
}

pub enum Direction {
	client_to_engine
	engine_to_client
}

pub struct Header {
pub:
	op           Op
	request      u64
	view         u64
	generation   u64
	navigation   u64
	payload_size u32
}

fn command(op Op) bool {
	return u16(op) < 256
}

fn valid_op(number u16) !Op {
	return match number {
		1 { .create }
		2 { .resize }
		3 { .navigate }
		4 { .javascript }
		5 { .pointer }
		6 { .key }
		7 { .text }
		8 { .scroll }
		9 { .destroy }
		10 { .cookie_set }
		11 { .cookie_get }
		12 { .cookie_delete }
		13 { .policy_reply }
		256 { .ack }
		257 { .pixels }
		258 { .navigation }
		259 { .failure }
		260 { .cookie_result }
		261 { .policy_request }
		else { return error('unknown browser operation') }
	}
}

fn (h Header) validate(direction Direction) ! {
	valid_op(u16(h.op))!
	if command(h.op) != (direction == .client_to_engine) {
		return error('browser operation has wrong direction')
	}
	if h.payload_size > max_payload { return error('browser payload exceeds limit') }
	if h.op in [.cookie_set, .cookie_get, .cookie_delete, .cookie_result]
		|| (h.op in [.ack, .failure] && h.view == 0) {
		if h.view != 0 || h.generation != 0 || h.navigation != 0 || h.request == 0 {
			return error('cookie operation must address the channel network session')
		}
	} else {
		if h.view == 0 || h.generation == 0 { return error('browser view identity is missing') }
		if command(h.op) || h.op in [.ack, .policy_request] {
			if h.request == 0 { return error('browser request identity is missing') }
		}
		if h.op in [.navigate, .navigation, .policy_request, .policy_reply, .pixels]
			&& h.navigation == 0 {
			return error('browser navigation identity is missing')
		}
	}
}

// No principal/package/UID field exists. Those come from the authenticated
// launcher-owned channel and must never be accepted from a Java Context.
pub fn encode_header(h Header, direction Direction) ![]u8 {
	h.validate(direction)!
	mut bytes := []u8{len: header_size}
	bytes[0] = `V`
	bytes[1] = `B`
	bytes[2] = `R`
	bytes[3] = `1`
	binary.little_endian_put_u16(mut bytes[4..6], 1)
	binary.little_endian_put_u16(mut bytes[6..8], u16(h.op))
	binary.little_endian_put_u64(mut bytes[8..16], h.request)
	binary.little_endian_put_u64(mut bytes[16..24], h.view)
	binary.little_endian_put_u64(mut bytes[24..32], h.generation)
	binary.little_endian_put_u64(mut bytes[32..40], h.navigation)
	binary.little_endian_put_u32(mut bytes[40..44], h.payload_size)
	// Bytes 44..48 are reserved, zero in version 1.
	return bytes
}

pub fn decode_header(bytes []u8, direction Direction) !Header {
	if bytes.len != header_size || bytes[..4] != 'VBR1'.bytes()
		|| binary.little_endian_u16(bytes[4..6]) != 1
		|| binary.little_endian_u32(bytes[44..48]) != 0 {
		return error('invalid browser frame header')
	}
	h := Header{
		op:           valid_op(binary.little_endian_u16(bytes[6..8]))!
		request:      binary.little_endian_u64(bytes[8..16])
		view:         binary.little_endian_u64(bytes[16..24])
		generation:   binary.little_endian_u64(bytes[24..32])
		navigation:   binary.little_endian_u64(bytes[32..40])
		payload_size: binary.little_endian_u32(bytes[40..44])
	}
	h.validate(direction)!
	return h
}

fn text(bytes []u8, limit int, empty bool) ! {
	if bytes.len > limit || (!empty && bytes.len == 0) || bytes.contains(u8(0))
		|| !utf8.validate(bytes.data, bytes.len) {
		return error('invalid browser UTF-8 field')
	}
}

fn dimensions(bytes []u8) ! {
	if bytes.len != 8 { return error('invalid browser dimensions') }
	w := binary.little_endian_u32(bytes[..4])
	h := binary.little_endian_u32(bytes[4..8])
	if w == 0 || h == 0 || w > max_dimension || h > max_dimension {
		return error('browser dimensions exceed limit')
	}
}

// Each cookie string is an opaque value for the real WebKitCookieManager. The
// engine must parse its URI/cookie with WebKit/Soup, not maintain a second jar.
fn strings(bytes []u8, count int) ! {
	mut offset := 0
	for _ in 0 .. count {
		if bytes.len - offset < 4 { return error('short browser string length') }
		n := binary.little_endian_u32(bytes[offset..offset + 4])
		offset += 4
		if n > 64 * 1024 || u64(offset) + n > u64(bytes.len) {
			return error('invalid browser string length')
		}
		text(bytes[offset..offset + int(n)], 64 * 1024, false)!
		offset += int(n)
	}
	if offset != bytes.len { return error('trailing browser string data') }
}

// Validate before enqueueing a message on either main loop. Success never
// implies permission: channel ownership and view state are separate checks.
pub fn validate_payload(h Header, bytes []u8) ! {
	if u64(bytes.len) != h.payload_size || bytes.len > max_payload {
		return error('browser frame payload length mismatch')
	}
	match h.op {
		.create, .resize { dimensions(bytes)! }
		.navigate { text(bytes, 64 * 1024, false)! }
		.javascript {
			if bytes.len != 1 || bytes[0] > 1 { return error('invalid browser boolean') }
		}
		.policy_reply {
			if bytes.len != 9 || binary.little_endian_u64(bytes[..8]) == 0 || bytes[8] > 1 {
				return error('invalid browser policy reply')
			}
		}
		.pointer {
			if bytes.len != 12 || binary.little_endian_u32(bytes[..4]) >= max_dimension
				|| binary.little_endian_u32(bytes[4..8]) >= max_dimension || bytes[8] > 2
				|| bytes[9] > 5 || bytes[10] != 0 || bytes[11] != 0 {
				return error('invalid browser pointer event')
			}
		}
		.key {
			if bytes.len != 8 || binary.little_endian_u32(bytes[..4]) > 0x1fffffff
				|| bytes[4] > 1 || bytes[5] != 0 || bytes[6] != 0 || bytes[7] != 0 {
				return error('invalid browser key event')
			}
		}
		.text { text(bytes, max_text, false)! }
		.scroll {
			if bytes.len != 8 { return error('invalid browser scroll event') }
			for offset in [0, 4] {
				n := i32(binary.little_endian_u32(bytes[offset..offset + 4]))
				if n < -10000 || n > 10000 { return error('browser scroll exceeds limit') }
			}
		}
		.destroy, .ack {
			if bytes.len != 0 { return error('unexpected browser payload') }
		}
		.cookie_set { strings(bytes, 2)! }
		.cookie_get, .cookie_delete { strings(bytes, 1)! }
		.cookie_result { text(bytes, max_text, true)! }
		.navigation {
			if bytes.len < 2 || bytes[0] > 3 { return error('invalid browser navigation event') }
			text(bytes[1..], 64 * 1024, false)!
		}
		.failure { text(bytes, 4096, false)! }
		.policy_request {
			if bytes.len < 9 || binary.little_endian_u64(bytes[..8]) == 0 {
				return error('invalid browser policy identity')
			}
			text(bytes[8..], 64 * 1024, false)!
		}
		.pixels {
			if bytes.len < 16 { return error('short browser pixel header') }
			dimensions(bytes[..8])!
			w := binary.little_endian_u32(bytes[..4])
			hgt := binary.little_endian_u32(bytes[4..8])
			stride := binary.little_endian_u32(bytes[8..12])
			format := binary.little_endian_u32(bytes[12..16])
			if stride != w * 4 || format != 1 || u64(stride) * hgt + 16 != u64(bytes.len) {
				return error('invalid browser premultiplied BGRA frame')
			}
		}
	}
}
