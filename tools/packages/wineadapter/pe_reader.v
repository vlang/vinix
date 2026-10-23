// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import encoding.utf8

// The pinned generic decoder grows array buffers without releasing old ones
// under -gc none. Parse this fixed nonrecursive schema into a noslices array,
// freeing partially decoded rows on error. Owned string parsing preserves JSON
// escapes/Unicode and bounds allocations, including malformed scalar input.
struct PeReader {
	text string
mut:
	position int
}

fn (mut r PeReader) spaces() {
	for r.position < r.text.len && r.text[r.position] in [u8(` `), `\t`, `\r`, `\n`]! { r.position++ }
}

fn (mut r PeReader) expect(byte u8) ! {
	r.spaces()
	if r.position >= r.text.len || r.text[r.position] != byte { return error('invalid Win64 receipt JSON structure') }
	r.position++
}

fn (mut r PeReader) next(first bool, end u8) !bool {
	r.spaces()
	if r.position < r.text.len && r.text[r.position] == end { r.position++; return false }
	if !first { r.expect(`,`)! }
	r.spaces()
	if r.position >= r.text.len || r.text[r.position] == end { return error('incomplete Win64 receipt JSON member') }
	return true
}

// String decoder adapted from appsdk/window_reader.v, MIT licensed.
// Copyright (c) 2026 Alexander Medvednikov. Permission notice: appsdk/LICENSE.
fn (mut r PeReader) quoted(limit int) !string {
	r.spaces()
	r.expect(`"`)!
	mut bytes := []u8{cap: 64}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	for r.position < r.text.len {
		if bytes.len > limit { return error('Win64 receipt JSON string exceeds its bound') }
		byte := r.text[r.position]
		r.position++
		if byte == `"` {
			if bytes.len > limit || !utf8.validate(bytes.data, bytes.len) { return error('invalid Win64 receipt UTF-8 string') }
			return bytes.bytestr()
		}
		if byte < 32 { return error('unescaped Win64 receipt JSON control character') }
		if byte != `\\` { bytes << byte; continue }
		if r.position >= r.text.len { return error('incomplete Win64 receipt JSON escape') }
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
						return error('Win64 receipt Unicode escape needs a low surrogate')
					}
					r.position += 2
					low := r.hex_unit()!
					if low < 0xdc00 || low > 0xdfff { return error('invalid Win64 receipt low surrogate') }
					value = 0x10000 + ((value - 0xd800) << 10) + low - 0xdc00
				} else if value >= 0xdc00 && value <= 0xdfff { return error('unpaired Win64 receipt low surrogate') }
				if value < 0x80 { bytes << u8(value) }
				else if value < 0x800 { bytes << u8(0xc0 | (value >> 6)); bytes << u8(0x80 | (value & 63)) }
				else if value < 0x10000 {
					bytes << u8(0xe0 | (value >> 12)); bytes << u8(0x80 | ((value >> 6) & 63)); bytes << u8(0x80 | (value & 63))
				} else {
					bytes << u8(0xf0 | (value >> 18)); bytes << u8(0x80 | ((value >> 12) & 63))
					bytes << u8(0x80 | ((value >> 6) & 63)); bytes << u8(0x80 | (value & 63))
				}
			}
			else { return error('invalid Win64 receipt JSON escape') }
		}
	}
	return error('unterminated Win64 receipt JSON string')
}

fn (mut r PeReader) hex_unit() !u32 {
	if r.position + 4 > r.text.len { return error('incomplete Win64 receipt Unicode escape') }
	mut value := u32(0)
	for _ in 0 .. 4 {
		byte := r.text[r.position]
		r.position++
		digit := if byte >= `0` && byte <= `9` { u32(byte - `0`) }
			else if byte >= `a` && byte <= `f` { u32(byte - `a` + 10) }
			else if byte >= `A` && byte <= `F` { u32(byte - `A` + 10) }
			else { return error('invalid Win64 receipt Unicode hex digit') }
		value = (value << 4) | digit
	}
	return value
}

fn (mut r PeReader) member(input bool, seen u16) !int {
	key := r.quoted(32)!
	index := if input {
		match key { 'kind' { 0 } 'target' { 1 } 'sha256' { 2 } else { -1 } }
	} else {
		match key {
			'format' { 0 } 'scope' { 1 } 'compiler' { 2 } 'mingw_root' { 3 } 'source' { 4 }
			'environment' { 5 } 'inputs' { 6 } 'outputs' { 7 } 'commands' { 8 } else { -1 }
		}
	}
	unsafe { key.free() }
	if index < 0 || seen & (u16(1) << index) != 0 { return error('unknown or duplicate Win64 receipt field') }
	r.expect(`:`)!
	return index
}

fn (mut r PeReader) format() !int {
	r.spaces()
	if r.position >= r.text.len || r.text[r.position] != `1` { return error('unsupported Win64 receipt format') }
	r.position++
	return 1
}

fn (mut r PeReader) string_map(maximum int, key_limit int, value_limit int) !map[string]string {
	r.expect(`{`)!
	mut values := map[string]string{}
	mut accepted := false
	defer { if !accepted { unsafe { for _, value in values { value.free() }; values.free() } } }
	mut first := true
	for r.next(first, `}`)! {
		first = false
		if values.len == maximum { return error('Win64 receipt map exceeds its entry bound') }
		key := r.quoted(key_limit)!
		defer { unsafe { key.free() } }
		if key in values { return error('duplicate Win64 receipt map key') }
		r.expect(`:`)!
		values[key] = r.quoted(value_limit)!
	}
	accepted = true
	return values
}

fn (mut r PeReader) input() !PeProofInput {
	r.expect(`{`)!
	mut value := PeProofInput{}
	mut accepted := false
	defer { if !accepted { unsafe { value.kind.free(); value.target.free(); value.sha256.free() } } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		index := r.member(true, seen)!
		seen |= u16(1) << index
		match index {
			0 { value = PeProofInput{...value, kind: r.quoted(16)!} }
			1 { value = PeProofInput{...value, target: r.quoted(4096)!} }
			else { value = PeProofInput{...value, sha256: r.quoted(64)!} }
		}
	}
	if seen != 7 { return error('incomplete Win64 receipt input') }
	accepted = true
	return value
}

fn (mut r PeReader) inputs() !map[string]PeProofInput {
	r.expect(`{`)!
	mut values := map[string]PeProofInput{}
	mut accepted := false
	defer { if !accepted { close_pe_inputs(values) } }
	mut first := true
	for r.next(first, `}`)! {
		first = false
		if values.len == 100000 { return error('Win64 receipt input inventory exceeds its entry bound') }
		key := r.quoted(4096)!
		defer { unsafe { key.free() } }
		if key in values { return error('duplicate Win64 receipt input path') }
		r.expect(`:`)!
		values[key] = r.input()!
	}
	accepted = true
	return values
}

fn (mut r PeReader) strings() ![]string {
	r.expect(`[`)!
	mut values := []string{cap: 32}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { unsafe { values.free() } } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if values.len == 32 { return error('Win64 receipt command exceeds its argument bound') }
		value := r.quoted(8192)!
		unsafe { values.push_many(&value, 1) }
	}
	accepted = true
	return values
}

fn (mut r PeReader) commands() ![][]string {
	r.expect(`[`)!
	mut values := [][]string{cap: 3}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { unsafe {
		for value in values { value.free() }
		(&array(&values)).free()
	} } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if values.len == 3 { return error('Win64 receipt exceeds its command bound') }
		value := r.strings()!
		unsafe { values.push_many(&value, 1) }
	}
	accepted = true
	return values
}

fn pe_decode(text string) !PeProofRecord {
	if text.len > 16 * 1024 * 1024 { return error('Win64 receipt exceeds its metadata bound') }
	mut r := &PeReader{text: text}
	defer { unsafe { free(r) } }
	r.expect(`{`)!
	mut record := PeProofRecord{}
	mut accepted := false
	defer { if !accepted { close_pe_record(record) } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		index := r.member(false, seen)!
		seen |= u16(1) << index
		match index {
			0 { record = PeProofRecord{...record, format: r.format()!} }
			1 { record = PeProofRecord{...record, scope: r.quoted(256)!} }
			2 { record = PeProofRecord{...record, compiler: r.quoted(4096)!} }
			3 { record = PeProofRecord{...record, mingw_root: r.quoted(4096)!} }
			4 { record = PeProofRecord{...record, source: r.quoted(4096)!} }
			5 {
				value := r.string_map(14, 128, 8192)!
				unsafe { record.environment.free() }
				record = PeProofRecord{...record, environment: value}
			}
			6 {
				value := r.inputs()!
				close_pe_inputs(record.inputs)
				record = PeProofRecord{...record, inputs: value}
			}
			7 {
				value := r.string_map(14, 128, 64)!
				unsafe { record.outputs.free() }
				record.outputs = value
			}
			else { record.commands = r.commands()! }
		}
	}
	r.spaces()
	if seen != 511 || r.position != text.len { return error('incomplete or trailing Win64 receipt JSON') }
	accepted = true
	return record
}

