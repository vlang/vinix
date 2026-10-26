// SPDX-License-Identifier: GPL-2.0-or-later
module fontindex

import compress.gzip
import os

struct Expansion {
mut:
	bytes    []u8
	limit    int
	exceeded bool
}

fn append_chunk(chunk []u8, opaque voidptr) int {
	mut output := unsafe { &Expansion(opaque) }
	if chunk.len > output.limit - output.bytes.len {
		output.exceeded = true
		return 0
	}
	output.bytes << chunk
	return chunk.len
}

fn expand(packed []u8, limit int) ![]u8 {
	mut output := Expansion{ limit: limit }
	gzip.decompress_with_callback(packed, append_chunk, &output) or {
		if output.exceeded { return error('PCF expansion exceeds limit') }
		return err
	}
	if output.exceeded { return error('PCF expansion exceeds limit') }
	return output.bytes
}

fn word(data []u8, offset int, big bool) !u32 {
	if offset < 0 || offset > data.len - 4 { return error('PCF word outside input') }
	return if big {
		u32(data[offset]) << 24 | u32(data[offset + 1]) << 16 | u32(data[offset + 2]) << 8 | data[offset + 3]
	} else {
		u32(data[offset]) | u32(data[offset + 1]) << 8 | u32(data[offset + 2]) << 16 | u32(data[offset + 3]) << 24
	}
}

fn text(data []u8, offset u32) !string {
	if offset >= u32(data.len) { return error('PCF property outside string table') }
	mut end := int(offset)
	for end < data.len && data[end] != 0 {
		if data[end] < 33 || data[end] > 126 { return error('invalid PCF property string') }
		end++
	}
	if end == int(offset) || end == data.len {
		return error('empty or unterminated PCF property string')
	}
	return data[int(offset)..end].bytestr()
}

// Only the FONT property is needed for Xvfb's fonts.dir. All offsets are bounded
// before interpreting the PCF property table; glyph/metric data stays opaque.
pub fn font_name(data []u8) !string {
	if data.len < 8 || data[..4] != [u8(1), `f`, `c`, `p`] { return error('invalid PCF header') }
	count := word(data, 4, false)!
	if count == 0 || count > 32 || u64(count) * 16 > u64(data.len - 8) {
		return error('invalid PCF table count')
	}
	mut table := []u8{}
	for i in 0 .. int(count) {
		at := 8 + i * 16
		if word(data, at, false)! != 1 { continue }
		if table.len != 0 { return error('duplicate PCF property table') }
		size, offset := word(data, at + 8, false)!, word(data, at + 12, false)!
		if offset > u32(data.len) || size > u32(data.len) - offset || size < 12 {
			return error('invalid PCF property span')
		}
		table = data[int(offset)..int(offset + size)]
	}
	if table.len == 0 { return error('PCF properties missing') }
	format := word(table, 0, false)!
	if format & ~u32(0x3f) != 0 { return error('unsupported PCF property format') }
	big := format & 4 != 0
	properties := word(table, 4, big)!
	if properties > 4096 || u64(properties) * 9 > u64(table.len - 8) {
		return error('invalid PCF property count')
	}
	string_offset := 8 + ((int(properties) * 9 + 3) & ~3)
	string_size := word(table, string_offset, big)!
	if string_offset + 4 > table.len || string_size > u32(table.len - string_offset - 4) {
		return error('invalid PCF string table size')
	}
	string_end := string_offset + 4 + int(string_size)
	padding := table[string_end..].clone()
	if padding.len > 3 || padding.any(it != 0) { return error('invalid PCF string table padding') }
	strings := table[string_offset + 4..string_end].clone()
	mut name := ''
	for i in 0 .. int(properties) {
		at := 8 + i * 9
		property := text(strings, word(table, at, big)!)!
		if property != 'FONT' { continue }
		if name != '' || table[at + 4] != 1 {
			return error('invalid or duplicate PCF FONT property')
		}
		name = text(strings, word(table, at + 5, big)!)!
	}
	// The X core cursor font is addressed by this exact legacy name.
	if name != 'cursor' && (!name.starts_with('-') || name.count('-') != 14) {
		return error('PCF FONT must be an XLFD name')
	}
	return name
}

pub fn write_index(directory string) ! {
	mut names := os.ls(directory)!
	names.sort()
	mut entries := []string{}
	mut fonts := map[string]bool{}
	for name in names {
		if !name.ends_with('.pcf.gz') && !name.ends_with('.pcf') { continue }
		path := directory + '/' + name
		if os.lstat(path)!.get_filetype() != .regular || os.file_size(path) > 4 * 1024 * 1024 {
			return error('expected bounded regular PCF font')
		}
		packed := os.read_bytes(path)!
		// Check the declared gzip size before decompression as well as afterwards.
		if name.ends_with('.gz') && (packed.len < 18 || word(packed, packed.len - 4, false)! > 16 * 1024 * 1024) {
			return error('PCF gzip expansion exceeds limit')
		}
		data := if name.ends_with('.gz') { expand(packed, 16 * 1024 * 1024)! } else { packed }
		if data.len > 16 * 1024 * 1024 { return error('PCF expansion exceeds limit') }
		font := font_name(data)!
		if font in fonts { return error('duplicate PCF FONT name') }
		fonts[font] = true
		entries << name + ' ' + font
	}
	if entries.len == 0 { return error('Xvfb bitmap fonts missing') }
	os.write_file(directory + '/fonts.dir', entries.len.str() + '\n' + entries.join('\n') + '\n')!
	os.chmod(directory + '/fonts.dir', 0o444)!
}
