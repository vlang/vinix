// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import encoding.utf8

// Bounded primitives for on-disk configuration and state. Kept internal to
// pkgcore: presentation readers retain their independent protocol contract.
// Adapted from pkgprotocol/metadata_reader.v; all results own their strings.
// The wider member mask supports complete persisted manifest declarations.
struct StoredReader {
	text string
mut:
	position int
}

fn (mut r StoredReader) spaces() {
	for r.position < r.text.len && r.text[r.position] in [u8(` `), `\t`, `\r`, `\n`]! { r.position++ }
}

fn (mut r StoredReader) expect(byte u8) ! {
	r.spaces()
	if r.position >= r.text.len || r.text[r.position] != byte { return error('invalid package metadata JSON structure') }
	r.position++
}

fn (mut r StoredReader) next(first bool, end u8) !bool {
	r.spaces()
	if r.position < r.text.len && r.text[r.position] == end { r.position++; return false }
	if !first { r.expect(`,`)! }
	r.spaces()
	if r.position >= r.text.len || r.text[r.position] == end { return error('incomplete package metadata JSON member') }
	return true
}

// String decoder adapted from appsdk/window_reader.v, MIT licensed.
// Copyright (c) 2026 Alexander Medvednikov. Permission notice: appsdk/LICENSE.
fn (mut r StoredReader) quoted(limit int) !string {
	r.spaces()
	r.expect(`"`)!
	mut bytes := []u8{cap: 64}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	for r.position < r.text.len {
		if bytes.len > limit { return error('package metadata JSON string exceeds its bound') }
		byte := r.text[r.position]
		r.position++
		if byte == `"` {
			if bytes.len > limit || !utf8.validate(bytes.data, bytes.len) { return error('invalid package metadata UTF-8 string') }
			return bytes.bytestr()
		}
		if byte < 32 { return error('unescaped package metadata JSON control character') }
		if byte != `\\` { bytes << byte; continue }
		if r.position >= r.text.len { return error('incomplete package metadata JSON escape') }
		escape := r.text[r.position]
		r.position++
		match escape {
			`"`, `\\`, `/` { bytes << escape }
			`n` { bytes << u8(10) }
			`r` { bytes << u8(13) }
			`t` { bytes << u8(9) }
			`b` { bytes << u8(8) }
			`f` { bytes << u8(12) }
			`u` {
				mut value := r.hex_unit()!
				if value >= 0xd800 && value <= 0xdbff {
					if r.position + 2 > r.text.len || r.text[r.position] != `\\` || r.text[r.position + 1] != `u` {
						return error('package metadata Unicode escape needs a low surrogate')
					}
					r.position += 2
					low := r.hex_unit()!
					if low < 0xdc00 || low > 0xdfff { return error('invalid package metadata low surrogate') }
					value = 0x10000 + ((value - 0xd800) << 10) + low - 0xdc00
				} else if value >= 0xdc00 && value <= 0xdfff { return error('unpaired package metadata low surrogate') }
				if value < 0x80 { bytes << u8(value) }
				else if value < 0x800 { bytes << u8(0xc0 | (value >> 6)); bytes << u8(0x80 | (value & 63)) }
				else if value < 0x10000 {
					bytes << u8(0xe0 | (value >> 12)); bytes << u8(0x80 | ((value >> 6) & 63)); bytes << u8(0x80 | (value & 63))
				} else {
					bytes << u8(0xf0 | (value >> 18)); bytes << u8(0x80 | ((value >> 12) & 63))
					bytes << u8(0x80 | ((value >> 6) & 63)); bytes << u8(0x80 | (value & 63))
				}
			}
			else { return error('invalid package metadata JSON escape') }
		}
	}
	return error('unterminated package metadata JSON string')
}

fn (mut r StoredReader) hex_unit() !u32 {
	if r.position + 4 > r.text.len { return error('incomplete package metadata Unicode escape') }
	mut value := u32(0)
	for _ in 0 .. 4 {
		byte := r.text[r.position]
		r.position++
		digit := if byte >= `0` && byte <= `9` { u32(byte - `0`) }
			else if byte >= `a` && byte <= `f` { u32(byte - `a` + 10) }
			else if byte >= `A` && byte <= `F` { u32(byte - `A` + 10) }
			else { return error('invalid package metadata Unicode hex digit') }
		value = (value << 4) | digit
	}
	return value
}

fn (mut r StoredReader) member(keys []string, seen u32) !int {
	key := r.quoted(32)!
	index := keys.index(key)
	unsafe { key.free() }
	if index < 0 || seen & (u32(1) << index) != 0 { return error('unknown or duplicate package metadata JSON field') }
	r.expect(`:`)!
	return index
}

fn (mut r StoredReader) boolean() !bool {
	r.spaces()
	for value in ['true', 'false']! {
		if r.position + value.len <= r.text.len
			&& unsafe { tos(r.text.str + r.position, value.len) } == value {
			r.position += value.len
			return value == 'true'
		}
	}
	return error('package metadata field must be a boolean')
}

fn (mut r StoredReader) unsigned(maximum u64) !u64 {
	r.spaces()
	start := r.position
	mut value := u64(0)
	for r.position < r.text.len && r.text[r.position] >= `0` && r.text[r.position] <= `9` {
		digit := u64(r.text[r.position] - `0`)
		if (r.position > start && r.text[start] == `0`) || value > maximum / 10
			|| (value == maximum / 10 && digit > maximum % 10) { return error('package metadata integer exceeds its canonical bound') }
		value = value * 10 + digit
		r.position++
	}
	if r.position == start { return error('package metadata requires an unsigned integer') }
	return value
}

fn (mut r StoredReader) strings(limit int, maximum int) ![]string {
	return r.strings_with_limit(limit, maximum, 'package metadata array exceeds its entry limit')
}

fn (mut r StoredReader) strings_with_limit(limit int, maximum int, overflow string) ![]string {
	r.expect(`[` )!
	mut values := []string{cap: 16}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { unsafe { for value in values { value.free() }; (&array(&values)).free() } } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if values.len == maximum { return error(overflow) }
		values << r.quoted(limit)!
	}
	accepted = true
	return values
}
