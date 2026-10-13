// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import encoding.utf8

const personal_data_keys = ['format', 'rows']
const personal_data_row_keys = ['id', 'installed', 'diagnostic']

pub struct PersonalData {
pub:
	id         string
	installed  bool
	diagnostic string
}

// An observation of the calling account's data, never permission to delete it.
// purge-data rechecks installed state, live generation leases and filesystem
// ownership after confirmation.
pub struct PersonalDataStatus {
pub:
	format int
	rows   []PersonalData
}

pub fn decode_personal_data(text string) !PersonalDataStatus {
	if text.len > 8 * 1024 * 1024 { return error('personal data status exceeds metadata limit') }
	mut reader := &PersonalDataReader{ text: text }
	defer { unsafe { free(reader) } }
	reader.expect(`{`)!
	mut status := PersonalDataStatus{}
	mut accepted := false
	defer { if !accepted { status.close() } }
	mut seen := u8(0)
	mut first := true
	for reader.next(first, `}`)! {
		first = false
		field := reader.member(personal_data_keys, seen)!
		seen |= u8(1) << field
		if field == 0 {
			reader.expect(`1`)!
			status = PersonalDataStatus{ ...status, format: 1 }
		} else {
			status = PersonalDataStatus{ ...status, rows: reader.rows()! }
		}
	}
	reader.spaces()
	if seen != 3 || reader.position != text.len { return error('incomplete or trailing personal data status') }
	status.validate()!
	accepted = true
	return status
}

// The pinned generic decoder grows array buffers without releasing old ones
// under -gc none. Parse this fixed nonrecursive schema into a noslices array,
// freeing partially decoded rows on error. Owned string parsing preserves JSON
// escapes/Unicode and bounds allocations, including malformed scalar input.
struct PersonalDataReader {
	text string
mut:
	position int
}

fn (mut r PersonalDataReader) spaces() {
	for r.position < r.text.len && r.text[r.position] in [u8(` `), `\t`, `\r`, `\n`]! { r.position++ }
}

fn (mut r PersonalDataReader) expect(byte u8) ! {
	r.spaces()
	if r.position >= r.text.len || r.text[r.position] != byte { return error('invalid personal data JSON structure') }
	r.position++
}

fn (mut r PersonalDataReader) next(first bool, end u8) !bool {
	r.spaces()
	if r.position < r.text.len && r.text[r.position] == end { r.position++; return false }
	if !first { r.expect(`,`)! }
	r.spaces()
	if r.position >= r.text.len || r.text[r.position] == end { return error('incomplete personal data JSON member') }
	return true
}

// String decoder adapted from appsdk/window_reader.v, MIT licensed.
// Copyright (c) 2026 Alexander Medvednikov. Permission notice: appsdk/LICENSE.
fn (mut r PersonalDataReader) quoted(limit int) !string {
	r.spaces()
	r.expect(`"`)!
	mut bytes := []u8{cap: 64}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	for r.position < r.text.len {
		if bytes.len > limit { return error('personal data JSON string exceeds its bound') }
		byte := r.text[r.position]
		r.position++
		if byte == `"` {
			if bytes.len > limit || !utf8.validate(bytes.data, bytes.len) { return error('invalid personal data UTF-8 string') }
			return bytes.bytestr()
		}
		if byte < 32 { return error('unescaped personal data JSON control character') }
		if byte != `\\` { bytes << byte; continue }
		if r.position >= r.text.len { return error('incomplete personal data JSON escape') }
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
						return error('personal data Unicode escape needs a low surrogate')
					}
					r.position += 2
					low := r.hex_unit()!
					if low < 0xdc00 || low > 0xdfff { return error('invalid personal data low surrogate') }
					value = 0x10000 + ((value - 0xd800) << 10) + low - 0xdc00
				} else if value >= 0xdc00 && value <= 0xdfff { return error('unpaired personal data low surrogate') }
				if value < 0x80 { bytes << u8(value) }
				else if value < 0x800 { bytes << u8(0xc0 | (value >> 6)); bytes << u8(0x80 | (value & 63)) }
				else if value < 0x10000 {
					bytes << u8(0xe0 | (value >> 12)); bytes << u8(0x80 | ((value >> 6) & 63)); bytes << u8(0x80 | (value & 63))
				} else {
					bytes << u8(0xf0 | (value >> 18)); bytes << u8(0x80 | ((value >> 12) & 63))
					bytes << u8(0x80 | ((value >> 6) & 63)); bytes << u8(0x80 | (value & 63))
				}
			}
			else { return error('invalid personal data JSON escape') }
		}
	}
	return error('unterminated personal data JSON string')
}

fn (mut r PersonalDataReader) hex_unit() !u32 {
	if r.position + 4 > r.text.len { return error('incomplete personal data Unicode escape') }
	mut value := u32(0)
	for _ in 0 .. 4 {
		byte := r.text[r.position]
		r.position++
		digit := if byte >= `0` && byte <= `9` { u32(byte - `0`) }
			else if byte >= `a` && byte <= `f` { u32(byte - `a` + 10) }
			else if byte >= `A` && byte <= `F` { u32(byte - `A` + 10) }
			else { return error('invalid personal data Unicode hex digit') }
		value = (value << 4) | digit
	}
	return value
}

fn (mut r PersonalDataReader) member(keys []string, seen u8) !int {
	key := r.quoted(32)!
	index := keys.index(key)
	unsafe { key.free() }
	if index < 0 || seen & (u8(1) << index) != 0 { return error('unknown or duplicate personal data JSON field') }
	r.expect(`:`)!
	return index
}

fn (mut r PersonalDataReader) boolean() !bool {
	r.spaces()
	for value in ['true', 'false']! {
		if r.position + value.len <= r.text.len
			&& unsafe { tos(r.text.str + r.position, value.len) } == value {
			r.position += value.len
			return value == 'true'
		}
	}
	return error('personal data installed field must be a boolean')
}

fn (mut r PersonalDataReader) row() !PersonalData {
	r.expect(`{`)!
	mut row := PersonalData{}
	mut accepted := false
	defer { if !accepted { unsafe { row.id.free(); row.diagnostic.free() } } }
	mut seen := u8(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(personal_data_row_keys, seen)!
		seen |= u8(1) << field
		match field {
			0 { row = PersonalData{ ...row, id: r.quoted(128)! } }
			1 { row = PersonalData{ ...row, installed: r.boolean()! } }
			2 { row = PersonalData{ ...row, diagnostic: r.quoted(512)! } }
			else {}
		}
	}
	if seen != 7 { return error('missing personal data row field') }
	accepted = true
	return row
}

fn (mut r PersonalDataReader) rows() ![]PersonalData {
	r.expect(`[` )!
	mut rows := []PersonalData{cap: 16}
	unsafe { rows.flags |= .noslices }
	mut accepted := false
	defer {
		if !accepted {
			mut discarded := PersonalDataStatus{ rows: rows }
			discarded.close()
		}
	}
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if rows.len == 4096 { return error('personal data row count exceeds its bound') }
		row := r.row()!
		pointer := unsafe { &row }
		unsafe { rows.push_many(pointer, 1) }
	}
	accepted = true
	return rows
}

pub fn (status &PersonalDataStatus) validate() ! {
	if status.format != 1 || status.rows.len > 4096 { return error('unsupported personal data status') }
	for index, row in status.rows {
		if !identifier(row.id) || (row.diagnostic != '' && !printable(row.diagnostic, 512)) {
			return error('invalid personal data entry')
		}
		for previous in 0 .. index {
			if status.rows[previous].id == row.id { return error('duplicate personal data ID') }
		}
	}
}

pub fn (mut status PersonalDataStatus) close() {
	unsafe {
		for row in status.rows { row.id.free(); row.diagnostic.free() }
		(&array(&status.rows)).free()
	}
	status = PersonalDataStatus{}
}
