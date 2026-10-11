// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

// All long-lived session records use inline, bounded storage. No allocation
// occurs on a poll, placement change, timer tick or clipboard selection.
pub const max_workspaces = 16
pub const max_windows = 128
pub const max_displays = 8
const hex_digits = '0123456789abcdef'

pub struct Text {
pub mut:
	bytes [512]u8
	len   int
}

pub fn (mut t Text) set(value string) ! {
	if value.len >= t.bytes.len || value.contains('\x00') {
		return error('text exceeds session record limit')
	}
	for i, byte in value { t.bytes[i] = byte }
	t.bytes[value.len] = 0
	t.len = value.len
}

pub fn text(value string) !Text {
	mut t := Text{}
	t.set(value)!
	return t
}

// Borrowed until the record changes. Callers that retain this string must clone.
pub fn (t &Text) str() string {
	return unsafe { tos(&t.bytes[0], t.len) }
}

pub struct Writer {
mut:
	bytes []u8 = []u8{cap: 16384}
}

pub fn (mut w Writer) add(value string) {
	unsafe { w.bytes.flags |= .noslices }
	for byte in value { w.bytes << byte }
}

pub fn (mut w Writer) number(value i64) {
	n := value.str()
	w.add(n)
	unsafe { n.free() }
}

pub fn (mut w Writer) field(value string) {
	unsafe { w.bytes.flags |= .noslices }
	for byte in value {
		w.bytes << hex_digits[int(byte >> 4)]
		w.bytes << hex_digits[int(byte & 15)]
	}
}

pub fn (mut w Writer) finish() string {
	result := unsafe { tos(w.bytes.data, w.bytes.len).clone() }
	unsafe { w.bytes.free() }
	w.bytes = []u8{}
	return result
}

pub fn unfield(value string) !Text {
	if value.len % 2 != 0 || value.len >= 1024 { return error('invalid encoded text') }
	mut out := Text{}
	for i := 0; i < value.len; i += 2 {
		hi := hex_digit(value[i])!
		lo := hex_digit(value[i + 1])!
		byte := u8(hi * 16 + lo)
		if byte == 0 { return error('NUL in session text') }
		out.bytes[out.len] = byte
		out.len++
	}
	return out
}

fn hex_digit(byte u8) !int {
	if byte >= `0` && byte <= `9` { return int(byte - `0`) }
	if byte >= `a` && byte <= `f` { return int(byte - `a`) + 10 }
	return error('invalid hex digit')
}

pub fn number(value string, minimum i64, maximum i64) !i64 {
	if value.len == 0 || value.len > 20 { return error('invalid number') }
	negative := value[0] == `-`
	start := if negative { 1 } else { 0 }
	if start == value.len { return error('invalid number') }
	mut n := i64(0)
	for i in start .. value.len {
		byte := value[i]
		if byte < `0` || byte > `9` || n > (i64(9223372036854775807) - i64(byte - `0`)) / 10 {
			return error('invalid or overflowing number')
		}
		n = n * 10 + i64(byte - `0`)
	}
	if negative { n = -n }
	if n < minimum || n > maximum { return error('number outside allowed range') }
	return n
}

// Split into borrowed slices; no per-field strings are retained by the parser.
pub struct Fields {
pub mut:
	values [32]string
	count  int
}

pub fn fields(line string) !Fields {
	mut result := Fields{}
	mut start := 0
	for end in 0 .. line.len + 1 {
		if end < line.len && line[end] != `\t` { continue }
		if result.count == result.values.len { return error('too many fields') }
		result.values[result.count] = unsafe { tos(&line.str[start], end - start) }
		result.count++
		start = end + 1
	}
	return result
}

pub fn identifier(value string) bool {
	if value.len == 0 || value.len > 128 { return false }
	for byte in value {
		if !((byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`)
			|| (byte >= `0` && byte <= `9`) || byte in [`-`, `_`, `.`]) {
			return false
		}
	}
	return true
}
