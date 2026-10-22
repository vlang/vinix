// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What goes over the authentication service's socket. One request, one
// reply, then the connection is closed. Both are a frame:
//
//	u32 magic      "VAUT"
//	u16 version
//	u16 code       the operation in a request, the status in a reply
//	u32 count      fields that follow, at most max_fields
//	count times:   u32 length (at most max_field), then that many bytes
//
// all little-endian. A field is bytes, not text: one of them is usually a
// password. Everything is bounded, and a frame that is anything but exactly
// this is refused whole.
module authproto

pub const magic = u32(0x54554156)
pub const version = u16(1)
pub const max_fields = 12
pub const max_field = 4096
pub const header_bytes = 12
pub const max_frame = header_bytes + max_fields * (4 + max_field)

// Requests.
pub const op_info = u16(1) // who the service takes the caller for
pub const op_verify = u16(2) // user, password
pub const op_change_password = u16(3) // user, old password, new password
pub const op_describe = u16(4) // action
pub const op_run = u16(5) // action, password, input, arguments...

// Replies.
pub const status_ok = u16(0)
pub const status_denied = u16(1) // wrong password, or not allowed to ask
pub const status_wait = u16(2) // too many failures; field 0 is the seconds
pub const status_invalid = u16(3) // the request made no sense
pub const status_failed = u16(4) // allowed, but it did not work
pub const status_password_needed = u16(5) // ask again with the password

pub struct Frame {
pub mut:
	code   u16
	fields [][]u8
}

pub fn text_frame(code u16, fields ...string) Frame {
	mut frame := Frame{
		code: code
		fields: [][]u8{cap: fields.len}
	}
	unsafe { frame.fields.flags |= .noslices }
	for field in fields {
		bytes := field.bytes()
		unsafe { frame.fields.push_many(&bytes, 1) }
	}
	return frame
}

pub fn (f &Frame) text(index int) string {
	if index < 0 || index >= f.fields.len {
		return ''
	}
	return f.fields[index].bytestr()
}

// Overwrite every field: they may have held a password.
pub fn (mut f Frame) wipe() {
	for mut field in f.fields {
		wipe_bytes(field.data, field.len)
	}
}

// Release an owned text_frame/decode/read_frame result, wiping its fields
// first. A frame borrowing caller fields must only be wiped, not closed.
pub fn (mut f Frame) close() {
	f.wipe()
	unsafe {
		for field in f.fields { field.free() }
		(&array(&f.fields)).free()
	}
	f = Frame{}
}

fn put_u32(mut out []u8, value u32) {
	out << u8(value)
	out << u8(value >> 8)
	out << u8(value >> 16)
	out << u8(value >> 24)
}

fn get_u32(data []u8, at int) u32 {
	return u32(data[at]) | (u32(data[at + 1]) << 8) | (u32(data[at + 2]) << 16) | (u32(data[at + 3]) << 24)
}

pub fn encode(frame Frame) ![]u8 {
	if frame.fields.len > max_fields {
		return error('too many fields')
	}
	// Validate before allocating or copying any field, including a password.
	mut size := header_bytes
	for field in frame.fields {
		if field.len > max_field { return error('field too long') }
		size += 4 + field.len
	}
	mut out := []u8{cap: size}
	unsafe { out.flags |= .noslices }
	put_u32(mut out, magic)
	out << u8(version)
	out << u8(version >> 8)
	out << u8(frame.code)
	out << u8(frame.code >> 8)
	put_u32(mut out, u32(frame.fields.len))
	for field in frame.fields {
		put_u32(mut out, u32(field.len))
		out << field
	}
	return out
}

// The code and the number of fields a header announces.
pub fn decode_header(header []u8) !(u16, int) {
	if header.len != header_bytes {
		return error('short header')
	}
	if get_u32(header, 0) != magic {
		return error('not an authentication frame')
	}
	if u16(header[4]) | (u16(header[5]) << 8) != version {
		return error('unsupported protocol version')
	}
	count := get_u32(header, 8)
	if count > u32(max_fields) {
		return error('too many fields')
	}
	return u16(header[6]) | (u16(header[7]) << 8), int(count)
}

// A whole frame from exactly `data`.
pub fn decode(data []u8) !Frame {
	if data.len < header_bytes || data.len > max_frame {
		return error('invalid frame length')
	}
	code, count := decode_header(data[..header_bytes])!
	mut frame := Frame{
		code: code
		fields: [][]u8{cap: count}
	}
	unsafe { frame.fields.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { frame.close() } }
	mut at := header_bytes
	for _ in 0 .. count {
		if data.len - at < 4 {
			return error('truncated frame')
		}
		length := get_u32(data, at)
		at += 4
		if length > u32(max_field) || u32(data.len - at) < length {
			return error('truncated frame')
		}
		field := unsafe { data[at..at + int(length)] }.clone()
		unsafe { frame.fields.push_many(&field, 1) }
		at += int(length)
	}
	if at != data.len {
		return error('bytes after the frame')
	}
	accepted = true
	return frame
}
