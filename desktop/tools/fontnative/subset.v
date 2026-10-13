// SPDX-License-Identifier: GPL-2.0-or-later
module fontnative

import encoding.binary

$if !font_sdk_custom ? {
	#pkgconfig harfbuzz-subset
}

#include <hb-subset.h>

fn C.hb_blob_create_or_fail(&char, u32, i32, voidptr, voidptr) voidptr
fn C.hb_blob_destroy(voidptr)
fn C.hb_blob_get_data(voidptr, &u32) &char
fn C.hb_face_create_or_fail(voidptr, u32) voidptr
fn C.hb_face_destroy(voidptr)
fn C.hb_face_reference_blob(voidptr) voidptr
fn C.hb_face_get_glyph_count(voidptr) u32
fn C.hb_face_collect_unicodes(voidptr, voidptr)
fn C.hb_set_create() voidptr
fn C.hb_set_destroy(voidptr)
fn C.hb_set_clear(voidptr)
fn C.hb_set_add(voidptr, u32)
fn C.hb_set_next(voidptr, &u32) i32
fn C.hb_subset_input_create_or_fail() voidptr
fn C.hb_subset_input_destroy(voidptr)
fn C.hb_subset_input_keep_everything(voidptr)
fn C.hb_subset_input_get_flags(voidptr) u32
fn C.hb_subset_input_set_flags(voidptr, u32)
fn C.hb_subset_input_unicode_set(voidptr) voidptr
fn C.hb_subset_input_set(voidptr, i32) voidptr
fn C.hb_subset_input_pin_axis_location(voidptr, voidptr, u32, f32) i32
fn C.hb_subset_or_fail(voidptr, voidptr) voidptr

struct Ttf {
mut:
	face       voidptr
	renamed    map[string]string
	timestamps []u8
}

fn ttf(data []u8) !Ttf {
	if data.len == 0 || u64(data.len) > u64(0xffffffff) { return error('invalid font data length') }
	blob := C.hb_blob_create_or_fail(unsafe { &char(data.data) }, u32(data.len), C.HB_MEMORY_MODE_DUPLICATE, unsafe { nil }, unsafe { nil })
	if blob == unsafe { nil } { return error('could not allocate font blob') }
	defer { C.hb_blob_destroy(blob) }
	face := C.hb_face_create_or_fail(blob, 0)
	if face == unsafe { nil } { return error('invalid SFNT font') }
	if C.hb_face_get_glyph_count(face) == 0 {
		C.hb_face_destroy(face)
		return error('font has no glyphs')
	}
	tables := sfnt_tables(data) or {
		C.hb_face_destroy(face)
		return err
	}
	head := tables['head'] or {
		C.hb_face_destroy(face)
		return error('font header missing')
	}
	if head.len < 36 {
		C.hb_face_destroy(face)
		return error('font header truncated')
	}
	return Ttf{ face: face, timestamps: head[20..36].clone() }
}

fn (mut font Ttf) close() {
	if font.face != unsafe { nil } {
		C.hb_face_destroy(font.face)
		font.face = unsafe { nil }
	}
}

fn (font &Ttf) bytes() ![]u8 {
	if font.face == unsafe { nil } { return error('font is closed') }
	blob := C.hb_face_reference_blob(font.face)
	if blob == unsafe { nil } { return error('font serialization failed') }
	defer { C.hb_blob_destroy(blob) }
	mut length := u32(0)
	data := C.hb_blob_get_data(blob, &length)
	if length == 0 || data == unsafe { nil } { return error('font blob is empty') }
	return unsafe { tos(data, int(length)).bytes() }
}

fn (font &Ttf) cmap() ![]int {
	if font.face == unsafe { nil } { return error('font is closed') }
	set := C.hb_set_create()
	if set == unsafe { nil } { return error('could not allocate font coverage set') }
	defer { C.hb_set_destroy(set) }
	C.hb_face_collect_unicodes(font.face, set)
	mut point := u32(0xffffffff)
	mut points := []int{}
	for C.hb_set_next(set, &point) != 0 { points << int(point) }
	return points
}

fn (mut font Ttf) subset(points []int, name_ids []int) ! {
	input := C.hb_subset_input_create_or_fail()
	if input == unsafe { nil } { return error('could not allocate subset options') }
	defer { C.hb_subset_input_destroy(input) }
	unicodes := C.hb_subset_input_unicode_set(input)
	C.hb_set_clear(unicodes)
	for point in points {
		if point < 0 || point > 0x10ffff { return error('invalid subset code point') }
		C.hb_set_add(unicodes, u32(point))
	}
	names := C.hb_subset_input_set(input, C.HB_SUBSET_SETS_NAME_ID)
	C.hb_set_clear(names)
	for id in [...[0, 1, 2, 3, 4, 5, 6], ...name_ids] { C.hb_set_add(names, u32(id)) }
	C.hb_set_clear(C.hb_subset_input_set(input, C.HB_SUBSET_SETS_LAYOUT_FEATURE_TAG))
	result := C.hb_subset_or_fail(font.face, input)
	if result == unsafe { nil } { return error('font subsetting failed') }
	C.hb_face_destroy(font.face)
	font.face = result
}

fn (font &Ttf) instantiate(weight int) !Ttf {
	input := C.hb_subset_input_create_or_fail()
	if input == unsafe { nil } { return error('could not allocate variable font options') }
	defer { C.hb_subset_input_destroy(input) }
	C.hb_subset_input_keep_everything(input)
	// fontTools' default static instantiation marks overlapping outlines.
	// FreeType uses this flag when choosing grayscale rasterization precision.
	C.hb_subset_input_set_flags(input, C.hb_subset_input_get_flags(input) | u32(C.HB_SUBSET_FLAGS_SET_OVERLAPS_FLAG))
	if C.hb_subset_input_pin_axis_location(input, font.face, 0x77676874, f32(weight)) == 0 {
		return error('font has no usable weight axis')
	}
	result := C.hb_subset_or_fail(font.face, input)
	if result == unsafe { nil } { return error('variable font instantiation failed') }
	return Ttf{ face: result, timestamps: font.timestamps.clone() }
}

struct NameRecord {
	id       int
	platform int
	encoding int
	language int
	data     []u8
}

fn name_key(record NameRecord) string {
	return record.id.str() + ':' + record.platform.str() + ':' + record.encoding.str() + ':' + record.language.str()
}

fn sfnt_tables(data []u8) !map[string][]u8 {
	if data.len < 12 || data[..4] !in [[u8(0), 1, 0, 0], 'OTTO'.bytes()] {
		return error('unsupported SFNT header')
	}
	count := int(binary.big_endian_u16_at(data, 4))
	if count == 0 || 12 + count * 16 > data.len { return error('font directory truncated') }
	mut tables := map[string][]u8{}
	for i in 0 .. count {
		at := 12 + i * 16
		name := data[at..at + 4].bytestr()
		start, size := u64(binary.big_endian_u32_at(data, at + 8)), u64(binary.big_endian_u32_at(data, at + 12))
		if start + size > u64(data.len) || name in tables {
			return error('font table invalid or duplicated')
		}
		tables[name] = data[int(start)..int(start + size)].clone()
	}
	return tables
}

fn name_records(data []u8) ![]NameRecord {
	if data.len < 6 || binary.big_endian_u16_at(data, 0) != 0 {
		return error('unsupported font name table')
	}
	count, storage := int(binary.big_endian_u16_at(data, 2)), int(binary.big_endian_u16_at(data, 4))
	if 6 + count * 12 > data.len || storage < 6 + count * 12 {
		return error('name records truncated')
	}
	mut records := []NameRecord{cap: count}
	for i in 0 .. count {
		at := 6 + i * 12
		size, offset := int(binary.big_endian_u16_at(data, at + 8)), int(binary.big_endian_u16_at(data, at + 10))
		if storage + offset + size > data.len { return error('name string truncated') }
		records << NameRecord{int(binary.big_endian_u16_at(data, at + 6)), int(binary.big_endian_u16_at(data, at)), int(binary.big_endian_u16_at(data, at + 2)), int(binary.big_endian_u16_at(data, at + 4)), data[storage + offset..storage + offset + size].clone()}
	}
	return records
}

fn u16_bytes(value int) []u8 {
	mut data := []u8{len: 2}
	binary.big_endian_put_u16(mut data, u16(value))
	return data
}

fn u32_bytes(value u32) []u8 {
	mut data := []u8{len: 4}
	binary.big_endian_put_u32(mut data, value)
	return data
}

fn checksum(data []u8) u32 {
	mut sum := u32(0)
	for start := 0; start < data.len; start += 4 {
		mut word := u32(0)
		for i in 0 .. 4 {
			word = (word << 8) | if start + i < data.len { u32(data[start + i]) } else { u32(0) }
		}
		sum += word
	}
	return sum
}

fn (font &Ttf) records() ![]NameRecord {
	tables := sfnt_tables(font.bytes()!)!
	return name_records(tables['name'] or { return error('font names missing') })!
}

fn (font &Ttf) publication() ![]u8 {
	data := font.bytes()!
	mut tables := sfnt_tables(data)!
	records := name_records(tables['name'] or { return error('font names missing') })!
	mut names := []u8{}
	mut entries := []u8{}
	for record in records {
		mut text := record.data.clone()
		key := name_key(record)
		if key in font.renamed {
			value := font.renamed[key]
			if !value.bytes().all(it < 128) { return error('subset family names must be ASCII') }
			text = []u8{}
			for byte in value.bytes() {
				if record.platform in [0, 3] { text << u8(0) }
				text << byte
			}
		}
		if names.len > 65535 || text.len > 65535 {
			return error('font name strings exceed SFNT limits')
		}
		for value in [record.platform, record.encoding, record.language, record.id, text.len,
			names.len] {
			entries << u16_bytes(value)
		}
		names << text
	}
	tables['name'] = [...u16_bytes(0), ...u16_bytes(records.len), ...u16_bytes(6 + records.len * 12),
		...entries, ...names]
	mut head := tables['head'] or { return error('font header missing') }
	if head.len < 36 || font.timestamps.len != 16 { return error('font timestamp fields missing') }
	for i in 0 .. 4 { head[8 + i] = 0 }
	copy(mut head[20..36], font.timestamps)
	tables['head'] = head
	keys := tables.keys().sorted()
	mut power, selector := 1, 0
	for power * 2 <= keys.len {
		power *= 2
		selector++
	}
	mut output := [...data[..4], ...u16_bytes(keys.len), ...u16_bytes(power * 16),
		...u16_bytes(selector), ...u16_bytes(keys.len * 16 - power * 16)]
	mut directory := []u8{}
	mut bodies := []u8{}
	mut head_at := 0
	for key in keys {
		table := tables[key]
		offset := 12 + keys.len * 16 + bodies.len
		if key == 'head' { head_at = offset }
		directory << key.bytes()
		for value in [checksum(table), u32(offset), u32(table.len)] {
			directory << u32_bytes(value)
		}
		bodies << table
		for bodies.len % 4 != 0 { bodies << u8(0) }
	}
	output << directory
	output << bodies
	binary.big_endian_put_u32(mut output[head_at + 8..head_at + 12], u32(0xb1b0afba) - checksum(output))
	return output
}
