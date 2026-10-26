// SPDX-License-Identifier: GPL-2.0-or-later
module accountmanifest

import encoding.utf8

const resource_table_limit = 128 * 1024 * 1024

// Return only a compiled XML file name. Resource aliases and configuration
// variants with different files are rejected instead of choosing host locale
// or trusting a string outside this APK's global resource pool.
pub fn resource_file(table []u8, resource_id u32) !string {
	if table.len < 12 || table.len > resource_table_limit || le16(table, 0) != 2
		|| le16(table, 2) != 12 || int(le32(table, 4)) != table.len
		|| resource_id >> 24 == 0 || resource_id & 0x00ff0000 == 0 {
		return error('invalid authenticator resource table')
	}
	expected_packages := le32(table, 8)
	if expected_packages == 0 || expected_packages > 256 {
		return error('invalid authenticator resource package count')
	}
	mut pool := []u8{}
	mut packages := u32(0)
	mut seen_packages := [256]bool{}
	mut result := ''
	mut found := false
	mut accepted := false
	defer { if !accepted && found { unsafe { result.free() } } }
	mut chunks := 0
	mut cursor := 12
	for cursor < table.len {
		kind, header, size := resource_chunk(table, cursor)!
		chunks++
		if chunks > 65536 { return error('too many authenticator resource chunks') }
		chunk := table[cursor..cursor + size]
		match kind {
			1 {
				if pool.len != 0 || packages != 0 {
					return error('duplicate or misplaced resource string pool')
				}
				resource_pool_bounds(chunk, header)!
				pool = unsafe { chunk } // read-only borrow within table's lifetime
			}
			0x200 {
				if pool.len == 0 || header < 284 { return error('invalid resource package header') }
				package_id := le32(chunk, 8)
				if package_id == 0 || package_id > 255 || seen_packages[int(package_id)] {
					return error('invalid or duplicate resource package ID')
				}
				seen_packages[int(package_id)] = true
				packages++
				if package_id == resource_id >> 24 {
					result, found = resource_package_file(chunk, header, pool, resource_id)!
				}
			}
			else { return error('unsupported resource table child') }
		}
		cursor += size
	}
	if packages != expected_packages || !found {
		return error('authenticator XML resource is absent')
	}
	accepted = true
	return result
}

fn resource_chunk(data []u8, at int) !(u16, int, int) {
	if at < 0 || at > data.len - 8 { return error('truncated resource chunk') }
	header, size := int(le16(data, at + 2)), int(le32(data, at + 4))
	if header < 8 || header & 3 != 0 || size < header || size & 3 != 0 || size > data.len - at {
		return error('invalid resource chunk bounds')
	}
	return le16(data, at), header, size
}

fn resource_pool_bounds(pool []u8, header int) ! {
	if header < 28 || pool.len < header { return error('invalid resource string pool') }
	count, styles := le32(pool, 8), le32(pool, 12)
	start, style_start := le32(pool, 20), le32(pool, 24)
	if count > 1024 * 1024 || styles > count || le32(pool, 16) & ~u32(0x101) != 0
		|| u64(start) < u64(header) + u64(count + styles) * 4 || start > u32(pool.len)
		|| (styles == 0 && style_start != 0)
		|| (styles != 0 && (style_start < start || style_start > u32(pool.len))) {
		return error('invalid resource string pool bounds')
	}
	end := if style_start != 0 { style_start } else { u32(pool.len) }
	for i in 0 .. int(count) {
		if le32(pool, header + i * 4) >= end - start {
			return error('resource string offset out of bounds')
		}
	}
	if styles != 0 {
		for i in 0 .. int(styles) {
			offset := le32(pool, header + (int(count) + i) * 4)
			if offset != absent && (offset & 3 != 0 || u64(offset) + 12 > u64(pool.len) - style_start) {
				return error('resource style offset out of bounds')
			}
		}
	}
}

fn resource_pool_string(pool []u8, index u32) !string {
	header := int(le16(pool, 2))
	resource_pool_bounds(pool, header)!
	if index >= le32(pool, 8) { return error('resource string index out of bounds') }
	start := int(le32(pool, 20))
	style_start := int(le32(pool, 24))
	end := if style_start != 0 { style_start } else { pool.len }
	offset := int(le32(pool, header + int(index) * 4))
	utf8_pool := le32(pool, 16) & 0x100 != 0
	units, next := pool_length(pool[..end], start + offset, utf8_pool)!
	if units > 4096 { return error('resource string exceeds limit') }
	if utf8_pool {
		length, at := pool_length(pool[..end], next, true)!
		if length > 4096 || length >= end - at || pool[at + length] != 0 {
			return error('invalid resource UTF-8 string bounds')
		}
		value := pool[at..at + length].bytestr()
		mut accepted := false
		defer { if !accepted { unsafe { value.free() } } }
		if !utf8.validate_str(value) || value.contains('\x00') {
			return error('invalid resource UTF-8')
		}
		mut actual_units := 0
		for i in 0 .. value.len {
			if value[i] & 0xc0 != 0x80 {
				actual_units += if value[i] & 0xf8 == 0xf0 { 2 } else { 1 }
			}
		}
		if actual_units != units { return error('resource UTF-8 length mismatch') }
		accepted = true
		return value
	}
	if next > end - 2 || units > (end - next - 2) / 2 || le16(pool, next + units * 2) != 0 {
		return error('invalid resource UTF-16 string bounds')
	}
	mut points := []rune{cap: units}
	defer { unsafe { points.free() } }
	mut at := next
	for at < next + units * 2 {
		first := u32(le16(pool, at))
		at += 2
		if first == 0 { return error('embedded null in resource string') }
		if first >= 0xd800 && first <= 0xdbff {
			if at >= next + units * 2 { return error('unpaired resource surrogate') }
			second := u32(le16(pool, at))
			at += 2
			if second < 0xdc00 || second > 0xdfff { return error('invalid resource surrogate') }
			points << rune(0x10000 + ((first - 0xd800) << 10) + second - 0xdc00)
		} else if first >= 0xdc00 && first <= 0xdfff {
			return error('unpaired resource surrogate')
		} else {
			points << rune(first)
		}
	}
	return points.string()
}

fn resource_package_file(package []u8, header int, pool []u8, resource_id u32) !(string, bool) {
	type_offset := if header >= 288 { le32(package, 284) } else { u32(0) }
	target_type := (resource_id >> 16) & 255
	if type_offset >= target_type { return error('invalid resource type ID offset') }
	local_type := target_type - type_offset
	types_at, keys_at := int(le32(package, 268)), int(le32(package, 276))
	if types_at < header || keys_at < header || types_at == keys_at {
		return error('invalid resource package string pool offsets')
	}
	type_kind, type_header, type_size := resource_chunk(package, types_at)!
	key_kind, key_header, key_size := resource_chunk(package, keys_at)!
	if type_kind != 1 || key_kind != 1 { return error('missing resource package string pools') }
	types := package[types_at..types_at + type_size]
	keys := package[keys_at..keys_at + key_size]
	resource_pool_bounds(types, type_header)!
	resource_pool_bounds(keys, key_header)!
	type_name := resource_pool_string(types, local_type - 1)!
	defer { unsafe { type_name.free() } }
	if type_name != 'xml' { return error('authenticator resource is not XML') }
	mut found := false
	mut result := ''
	mut accepted := false
	defer { if !accepted && found { unsafe { result.free() } } }
	mut cursor := header
	mut chunks := 0
	mut saw_types, saw_keys := false, false
	for cursor < package.len {
		kind, child_header, size := resource_chunk(package, cursor)!
		chunks++
		if chunks > 65536 { return error('too many resource package chunks') }
		if cursor == types_at { saw_types = kind == 1 }
		if cursor == keys_at { saw_keys = kind == 1 }
		if kind == 0x201 {
			chunk := package[cursor..cursor + size]
			if child_header < 24 || chunk[8] == 0 || le16(chunk, 10) != 0
				|| int(le32(chunk, 20)) != child_header - 20 {
				return error('invalid resource type header')
			}
			if u32(chunk[8]) == local_type {
				value, present := resource_type_file(chunk, child_header, pool, le32(keys, 8), u16(resource_id))!
				if present {
					if found {
						same := result == value
						unsafe { value.free() }
						if !same { return error('ambiguous authenticator XML resource variants') }
					} else {
						result, found = value, true
					}
				}
			}
		}
		cursor += size
	}
	if !saw_types || !saw_keys { return error('resource package pool is not a child chunk') }
	accepted = true
	return result, found
}

fn resource_type_file(chunk []u8, header int, pool []u8, key_count u32, target u16) !(string, bool) {
	flags, count := chunk[9], int(le32(chunk, 12))
	start := int(le32(chunk, 16))
	if flags !in [u8(0), 1, 2] || count > 65536 || start < header || start > chunk.len {
		return error('invalid resource entry index')
	}
	stride := if flags == 2 { 2 } else { 4 }
	if count > (start - header) / stride { return error('truncated resource entry index') }
	mut offset := absent
	mut previous := -1
	for i in 0 .. count {
		mut item := absent
		if flags == 1 {
			index := int(le16(chunk, header + i * 4))
			if index <= previous { return error('unsorted or duplicate sparse resource entry') }
			previous = index
			item = u32(le16(chunk, header + i * 4 + 2)) * 4
			if index == int(target) { offset = item }
		} else if flags == 2 {
			value := le16(chunk, header + i * 2)
			if value != 0xffff { item = u32(value) * 4 }
			if i == int(target) { offset = item }
		} else {
			item = le32(chunk, header + i * 4)
			if i == int(target) { offset = item }
		}
		if item != absent && (item & 3 != 0 || u64(item) + 8 > u64(chunk.len - start)) {
			return error('resource entry offset out of bounds')
		}
	}
	if offset == absent { return '', false }
	at := start + int(offset)
	entry_size, entry_flags := int(le16(chunk, at)), le16(chunk, at + 2)
	if entry_size < 8 || entry_size > chunk.len - at - 8 || entry_flags & ~u16(6) != 0
		|| le32(chunk, at + 4) >= key_count {
		return error('invalid or complex authenticator resource entry')
	}
	value_at := at + entry_size
	if le16(chunk, value_at) != 8 || chunk[value_at + 2] != 0 || chunk[value_at + 3] != 3 {
		return error('authenticator resource must be a direct string')
	}
	path := resource_pool_string(pool, le32(chunk, value_at + 4))!
	mut accepted := false
	defer { if !accepted { unsafe { path.free() } } }
	if path.len > 4096 || !path.starts_with('res/') || !path.ends_with('.xml')
		|| path.contains('\\') || path.contains('\x00') {
		return error('unsafe authenticator resource path')
	}
	mut segment := 0
	for i in 0 .. path.len + 1 {
		if i < path.len && (path[i] <= 32 || path[i] >= 127) {
			return error('unsafe authenticator resource path')
		}
		if i == path.len || path[i] == `/` {
			length := i - segment
			if length == 0 || (length == 1 && path[segment] == `.`)
				|| (length == 2 && path[segment] == `.` && path[segment + 1] == `.`) {
				return error('unsafe authenticator resource path')
			}
			segment = i + 1
		}
	}
	accepted = true
	return path, true
}
