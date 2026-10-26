// SPDX-License-Identifier: GPL-2.0-or-later
module accountmanifest

import compress.szip
import os
import strconv

fn rt_u16(mut out []u8, at int, value u16) {
	out[at], out[at + 1] = u8(value), u8(value >> 8)
}

fn rt_u32(mut out []u8, at int, value u32) {
	for i in 0 .. 4 { out[at + i] = u8(value >> (i * 8)) }
}

fn rt_chunk(kind u16, header int, size int) []u8 {
	mut out := []u8{len: size}
	rt_u16(mut out, 0, kind)
	rt_u16(mut out, 2, u16(header))
	rt_u32(mut out, 4, u32(size))
	return out
}

fn rt_pool(values []string, styled bool, utf16 bool) []u8 {
	start := 28 + (values.len + if styled { 1 } else { 0 }) * 4
	mut out := rt_chunk(1, 28, start)
	rt_u32(mut out, 8, u32(values.len))
	rt_u32(mut out, 12, if styled { u32(1) } else { 0 })
	rt_u32(mut out, 16, if utf16 { u32(0) } else { 0x100 })
	rt_u32(mut out, 20, u32(start))
	for i, value in values {
		assert value.len < 128
		rt_u32(mut out, 28 + i * 4, u32(out.len - start))
		if utf16 {
			out << [u8(value.len), 0]
			for item in value.bytes() { out << [item, 0] }
			out << [u8(0), 0]
		} else {
			out << [u8(value.len), u8(value.len)]
			out << value.bytes()
			out << u8(0)
		}
	}
	for out.len & 3 != 0 { out << u8(0) }
	if styled {
		rt_u32(mut out, 24, u32(out.len))
		rt_u32(mut out, 28 + values.len * 4, 0)
		out << []u8{len: 12, init: 0xff}
	}
	rt_u32(mut out, 4, u32(out.len))
	return out
}

fn rt_type(flags u8, entry u16, value u32) []u8 {
	count := if flags == 1 { 1 } else { int(entry) + 1 }
	stride := if flags == 2 { 2 } else { 4 }
	mut start := 24 + count * stride
	if start & 3 != 0 { start += 2 }
	mut out := rt_chunk(0x201, 24, start + 16)
	out[8], out[9] = 1, flags
	rt_u32(mut out, 12, u32(count))
	rt_u32(mut out, 16, u32(start))
	rt_u32(mut out, 20, 4)
	for i in 24 .. 24 + count * stride { out[i] = 0xff }
	if flags == 1 {
		rt_u16(mut out, 24, entry)
		rt_u16(mut out, 26, 0)
	} else if flags == 2 {
		rt_u16(mut out, 24 + int(entry) * 2, 0)
	} else {
		rt_u32(mut out, 24 + int(entry) * 4, 0)
	}
	rt_u16(mut out, start, 8)
	rt_u16(mut out, start + 8, 8)
	out[start + 11] = 3
	rt_u32(mut out, start + 12, value)
	return out
}

fn rt_table(flags u8, entry u16, variants []u32, paths []string, styled bool, utf16 bool, type_offset u32) []u8 {
	global := rt_pool(paths, styled, utf16)
	types := rt_pool(['xml'], false, false)
	keys := rt_pool(['authenticator'], false, false)
	mut package := rt_chunk(0x200, 288, 288)
	rt_u32(mut package, 8, 0x7f)
	rt_u32(mut package, 268, u32(package.len))
	package << types
	rt_u32(mut package, 276, u32(package.len))
	package << keys
	rt_u32(mut package, 284, type_offset)
	for value in variants { package << rt_type(flags, entry, value) }
	rt_u32(mut package, 4, u32(package.len))
	mut table := rt_chunk(2, 12, 12)
	rt_u32(mut table, 8, 1)
	table << global
	table << package
	rt_u32(mut table, 4, u32(table.len))
	return table
}

fn rt_reject(table []u8, id u32) {
	mut rejected := false
	resource_file(table, id) or { rejected = true }
	assert rejected
}

fn test_resource_file_supports_dense_sparse_offset16_and_package_offset() {
	for flags in [u8(0), 1, 2] {
		for offset in [u32(0), 4] {
			table := rt_table(flags, 19, [u32(0)], ['res/xml/account.xml'], false, false, offset)
			assert resource_file(table, 0x7f010013 + offset * 0x10000)! == 'res/xml/account.xml'
			rt_reject(table, 0x7f010012 + offset * 0x10000)
		}
	}
}

fn test_resource_file_styles_utf16_and_equal_configuration_variants() {
	for utf16 in [false, true] {
		table := rt_table(0, 0, [u32(0), 0], ['res/xml/account.xml'], true, utf16, 0)
		assert resource_file(table, 0x7f010000)! == 'res/xml/account.xml'
	}
	table := rt_table(0, 0, [u32(0), 1], ['res/xml/a.xml', 'res/xml/b.xml'], false, false, 0)
	rt_reject(table, 0x7f010000)
}

fn test_resource_file_rejects_path_escape_references_and_missing_values() {
	for path in ['../account.xml', 'res/../account.xml', 'res//account.xml', 'res/xml/a\\b.xml',
		'/res/xml/a.xml', 'res/xml/a.txt', 'res/xml/a\nb.xml', 'res/xml/a b.xml'] {
		rt_reject(rt_table(0, 0, [u32(0)], [path], false, false, 0), 0x7f010000)
	}
	rt_reject(rt_table(0, 0, [u32(1)], ['res/xml/a.xml'], false, false, 0), 0x7f010000)
	mut table := rt_table(0, 0, [u32(0)], ['res/xml/a.xml'], false, false, 0)
	table[table.len - 5] = 1 // TYPE_REFERENCE must not be followed implicitly.
	rt_reject(table, 0x7f010000)
	for invalid in [u32(0), 0x7f000000, 0x7e010000, 0x7f020000] {
		rt_reject(rt_table(0, 0, [u32(0)], ['res/xml/a.xml'], false, false, 0), invalid)
	}
}

fn test_resource_file_rejects_truncation_invalid_chunks_and_entry_bounds() {
	good := rt_table(0, 0, [u32(0)], ['res/xml/a.xml'], false, false, 0)
	for length in 0 .. good.len {
		rt_reject(good[..length], 0x7f010000)
		if length >= 12 && length & 3 == 0 {
			// Keep the root length consistent, exercising nested chunk bounds
			// rather than only rejecting at the outer file-size comparison.
			mut shortened := good[..length].clone()
			rt_u32(mut shortened, 4, u32(length))
			rt_reject(shortened, 0x7f010000)
		}
	}
	for mode in 0 .. 9 {
		mut table := good.clone()
		global_size := int(le32(table, 16))
		package_at := 12 + global_size
		type_at := package_at + int(le32(table, package_at + 276)) + int(le32(table, package_at + int(le32(table, package_at + 276)) + 4))
		match mode {
			0 { rt_u32(mut table, 8, 2) }
			1 { rt_u32(mut table, 12 + 20, 0xffffffff) }
			2 { rt_u32(mut table, package_at + 268, 0xffffffff) }
			3 { rt_u32(mut table, type_at + 24, 4) }
			4 { rt_u32(mut table, type_at + 16, 0xffffffff) }
			5 { rt_u16(mut table, type_at + 28 + 2, 1) }
			6 { rt_u32(mut table, type_at + 28 + 4, 1) }
			7 { table[type_at + 9] = 3 }
			else { rt_u32(mut table, type_at + 20, 5) }
		}
		rt_reject(table, 0x7f010000)
	}
}

fn test_resource_file_rejects_duplicate_packages_and_sparse_indices() {
	mut table := rt_table(0, 0, [u32(0)], ['res/xml/a.xml'], false, false, 0)
	package_at := 12 + int(le32(table, 16))
	duplicate := table[package_at..].clone()
	table << duplicate
	rt_u32(mut table, 4, u32(table.len))
	rt_u32(mut table, 8, 2)
	rt_reject(table, 0x7f010000)
	mut sparse := rt_type(1, 9, 0)
	rt_u32(mut sparse, 12, 2)
	// Two indices cannot fit before entriesStart.
	mut rejected := false
	resource_type_file(sparse, 24, rt_pool(['res/xml/a.xml'], false, false), 1, 9) or { rejected = true }
	assert rejected
	mut duplicate_index := rt_chunk(0x201, 24, 48)
	duplicate_index[8], duplicate_index[9] = 1, 1
	rt_u32(mut duplicate_index, 12, 2)
	rt_u32(mut duplicate_index, 16, 32)
	rt_u32(mut duplicate_index, 20, 4)
	rt_u16(mut duplicate_index, 24, 9)
	rt_u16(mut duplicate_index, 28, 9)
	rejected = false
	resource_type_file(duplicate_index, 24, rt_pool(['res/xml/a.xml'], false, false), 1, 9) or { rejected = true }
	assert rejected
}

// Optional retained-APK verification uses the exact same public parser. The
// input path, expected resource ID and file are supplied together by the audit
// runner, so no package-specific description is built into production code.
fn test_resource_file_retained_apk() {
	apk := os.getenv('VINIX_RESOURCE_TEST_APK')
	if apk == '' { return }
	id := strconv.parse_uint(os.getenv('VINIX_RESOURCE_TEST_ID'), 16, 32)!
	expected := os.getenv('VINIX_RESOURCE_TEST_FILE')
	assert expected != ''
	mut archive := szip.open(apk, .no_compression, .read_only)!
	defer { archive.close() }
	archive.open_entry('resources.arsc')!
	assert archive.size() <= u64(resource_table_limit)
	mut data := []u8{len: int(archive.size())}
	defer { unsafe { data.free() } }
	assert archive.read_entry_buf(data.data, data.len)! == data.len
	archive.close_entry()
	path := resource_file(data, u32(id))!
	defer { unsafe { path.free() } }
	assert path == expected
}
