// SPDX-License-Identifier: GPL-2.0-or-later
module accountmanifest

import compress.szip
import hash.crc32
import os
import rand

const fixture_package = 'com.google.android.gms'
const fixture_class = 'com.google.android.gms.auth.LoginActivity'

fn put16(mut data []u8, value u16) {
	data << u8(value)
	data << u8(value >> 8)
}

fn put32(mut data []u8, value u32) {
	put16(mut data, u16(value))
	put16(mut data, u16(value >> 16))
}

fn replace32(mut data []u8, at int, value u32) {
	for i in 0 .. 4 { data[at + i] = u8(value >> u32(i * 8)) }
}

fn fixture_chunk(kind u16, header u16, payload []u8) []u8 {
	mut out := []u8{}
	put16(mut out, kind)
	put16(mut out, header)
	put32(mut out, u32(payload.len + 8))
	out << payload
	return out
}

fn node(kind u16, payload []u8) []u8 {
	mut out := []u8{}
	put32(mut out, 1)
	put32(mut out, absent)
	out << payload
	return fixture_chunk(kind, 16, out)
}

fn fixture_pool(values []string, use_utf8 bool) []u8 {
	mut strings := []u8{}
	mut offsets := []u8{}
	for value in values {
		put32(mut offsets, u32(strings.len))
		mut units := []u16{}
		for point in value.runes() {
			if point <= 0xffff {
				units << u16(point)
			} else {
				units << u16(0xd800 + ((u32(point) - 0x10000) >> 10))
				units << u16(0xdc00 + ((u32(point) - 0x10000) & 0x3ff))
			}
		}
		if use_utf8 {
			assert units.len < 128 && value.len < 128
			strings << u8(units.len)
			strings << u8(value.len)
			strings << value.bytes()
			strings << u8(0)
		} else {
			put16(mut strings, u16(units.len))
			for unit in units { put16(mut strings, unit) }
			put16(mut strings, 0)
		}
	}
	for strings.len % 4 != 0 { strings << u8(0) }
	mut payload := []u8{}
	for value in [u32(values.len), 0, if use_utf8 { u32(0x100) } else { u32(0) },
		u32(28 + offsets.len), 0] {
		put32(mut payload, value)
	}
	payload << offsets
	payload << strings
	return fixture_chunk(1, 28, payload)
}

struct Attribute {
	ns      u32 = absent
	name    u32
	value   u32
	type_id u8  = 3
	raw     u32 = absent
}

fn fixture_start(name u32, attributes []Attribute) []u8 {
	mut payload := []u8{}
	put32(mut payload, absent)
	put32(mut payload, name)
	for value in [u16(20), 20, u16(attributes.len), 0, 0, 0] { put16(mut payload, value) }
	for attribute in attributes {
		put32(mut payload, attribute.ns)
		put32(mut payload, attribute.name)
		put32(mut payload, attribute.raw)
		put16(mut payload, 8)
		payload << u8(0)
		payload << attribute.type_id
		put32(mut payload, attribute.value)
	}
	return node(0x102, payload)
}

fn fixture_end(name u32) []u8 {
	mut payload := []u8{}
	put32(mut payload, absent)
	put32(mut payload, name)
	return node(0x103, payload)
}

fn namespace_node(kind u16, uri u32) []u8 {
	mut payload := []u8{}
	put32(mut payload, if uri == 11 { u32(13) } else { u32(8) })
	put32(mut payload, uri)
	return node(kind, payload)
}

struct Fixture {
	package_name        string = fixture_package
	class_name          string = '.auth.LoginActivity'
	use_utf8            bool   = true
	element             u32    = 4
	attribute_namespace u32    = 7
	attribute_name      u32    = 5
	attribute_type      u8     = 3
	raw                 u32    = absent
	duplicate           bool
	nested              bool
	duplicate_activity  bool
	wrong_end           bool
	pool_extra          string = 'supplementary: 😀'
}

fn fixture(options Fixture) []u8 {
	values := ['manifest', 'package', options.package_name, 'application', 'activity', 'name',
		options.class_name, android_namespace, 'a', 'activity-alias', 'wrapper',
		'https://foreign.example/android', options.pool_extra, 'foreign']
	mut payload := fixture_pool(values, options.use_utf8)
	payload << namespace_node(0x100, 7)
	payload << namespace_node(0x100, 11)
	payload << fixture_start(0, [Attribute{ name: 1, value: 2 }])
	payload << fixture_start(3, [])
	if options.nested { payload << fixture_start(10, []) }
	mut attributes := [Attribute{
		ns:      options.attribute_namespace
		name:    options.attribute_name
		value:   6
		type_id: options.attribute_type
		raw:     options.raw
	}]
	if options.duplicate { attributes << attributes[0] }
	for _ in 0 .. if options.duplicate_activity { 2 } else { 1 } {
		payload << fixture_start(options.element, attributes)
		payload << fixture_end(if options.wrong_end { u32(10) } else { options.element })
	}
	if options.nested { payload << fixture_end(10) }
	payload << fixture_end(3)
	payload << fixture_end(0)
	payload << namespace_node(0x101, 11)
	payload << namespace_node(0x101, 7)
	return fixture_chunk(3, 8, payload)
}

fn rejected(data []u8, package_name string, activity string) bool {
	verify_xml(data, package_name, activity) or { return true }
	return false
}

fn test_exact_activity_identity_and_android_component_name_forms() {
	for use_utf8 in [true, false] {
		for name in ['.auth.LoginActivity', fixture_class] {
			verify_xml(fixture(Fixture{ use_utf8: use_utf8, class_name: name }), fixture_package, fixture_class)!
		}
		verify_xml(fixture(Fixture{ use_utf8: use_utf8, class_name: 'LoginActivity' }), fixture_package,
			fixture_package + '.LoginActivity')!
	}
	assert rejected(fixture(Fixture{}), fixture_package, fixture_class + 'Other')
	assert rejected(fixture(Fixture{}), 'com.other.app', fixture_class)
	for option in [Fixture{ attribute_namespace: absent }, Fixture{ attribute_namespace: 11 },
		Fixture{ attribute_name: 1 }, Fixture{ element: 9 }, Fixture{ nested: true },
		Fixture{ duplicate: true }, Fixture{ duplicate_activity: true }, Fixture{ wrong_end: true },
		Fixture{ attribute_type: 1 }, Fixture{ raw: 2 }, Fixture{ class_name: '' },
		Fixture{ class_name: '.auth..LoginActivity' }, Fixture{ class_name: 'auth/Activity' }] {
		assert rejected(fixture(option), fixture_package, fixture_class)
	}
}

fn find_chunk(data []u8, kind u16) int {
	mut at := 8
	for at < data.len {
		if le16(data, at) == kind { return at }
		at += int(le32(data, at + 4))
	}
	panic('missing fixture chunk')
}

fn test_malformed_chunks_strings_references_and_entire_document_are_rejected() {
	valid := fixture(Fixture{})
	for length in 0 .. valid.len {
		mut short := valid[..length].clone()
		if length >= 8 { replace32(mut short, 4, u32(length)) }
		assert rejected(short, fixture_package, fixture_class), 'accepted truncation at ${length}'
	}
	pool := find_chunk(valid, 1)
	root := find_chunk(valid, 0x102)
	for point in [pool + 4, pool + 8, pool + 20, pool + 28, root + 4, root + 16, root + 20, root + 40,
		root + 52] {
		mut bad := valid.clone()
		replace32(mut bad, point, absent - 1)
		assert rejected(bad, fixture_package, fixture_class), 'accepted corruption at ${point}'
	}
	mut zero_chunk := valid.clone()
	replace32(mut zero_chunk, pool + 4, 0)
	assert rejected(zero_chunk, fixture_package, fixture_class)
	mut bad_utf8 := valid.clone()
	string_start := pool + int(le32(valid, pool + 20))
	bad_utf8[string_start + 2] = 0xff
	assert rejected(bad_utf8, fixture_package, fixture_class)
	mut bad_utf16 := fixture(Fixture{ use_utf8: false })
	utf16_start := 8 + int(le32(bad_utf16, 8 + 20))
	bad_utf16[utf16_start + 2] = 0x00
	bad_utf16[utf16_start + 3] = 0xd8
	assert rejected(bad_utf16, fixture_package, fixture_class)
	mut trailing := valid.clone()
	trailing << [u8(0), 0, 0, 0]
	replace32(mut trailing, 4, u32(trailing.len))
	assert rejected(trailing, fixture_package, fixture_class)
	mut mismatched_namespace := valid.clone()
	replace32(mut mismatched_namespace, mismatched_namespace.len - 4, 11)
	assert rejected(mismatched_namespace, fixture_package, fixture_class)
	mut duplicate_prefix := valid.clone()
	first_namespace := find_chunk(valid, 0x100)
	replace32(mut duplicate_prefix, first_namespace + 24 + 16, 8)
	assert rejected(duplicate_prefix, fixture_package, fixture_class)
	mut resources := []u8{len: 6 * 4}
	replace32(mut resources, 5 * 4, 0x01010003)
	resource_map := fixture_chunk(0x180, 8, resources)
	mut with_resources := valid.clone()
	with_resources.insert(first_namespace, resource_map)
	replace32(mut with_resources, 4, u32(with_resources.len))
	verify_xml(with_resources, fixture_package, fixture_class)!
	replace32(mut with_resources, first_namespace + 8 + 5 * 4, 0x01010001)
	assert rejected(with_resources, fixture_package, fixture_class)
}

struct Entry {
	name string
	data []u8
}

// Stored ZIP fixtures keep duplicate names and bad CRCs under test control.
fn apk_fixture(entries []Entry, corrupt_crc bool) []u8 {
	mut output := []u8{}
	mut directory := []u8{}
	for entry in entries {
		offset := output.len
		checksum := crc32.sum(entry.data) ^ if corrupt_crc { u32(1) } else { u32(0) }
		put32(mut output, 0x04034b50)
		for value in [u16(20), 0, 0, 0, 0] { put16(mut output, value) }
		for value in [checksum, u32(entry.data.len), u32(entry.data.len)] {
			put32(mut output, value)
		}
		put16(mut output, u16(entry.name.len))
		put16(mut output, 0)
		output << entry.name.bytes()
		output << entry.data
		put32(mut directory, 0x02014b50)
		for value in [u16(20), 20, 0, 0, 0, 0] { put16(mut directory, value) }
		for value in [checksum, u32(entry.data.len), u32(entry.data.len)] {
			put32(mut directory, value)
		}
		for value in [u16(entry.name.len), 0, 0, 0, 0] { put16(mut directory, value) }
		put32(mut directory, 0)
		put32(mut directory, u32(offset))
		directory << entry.name.bytes()
	}
	start := output.len
	output << directory
	put32(mut output, 0x06054b50)
	for value in [u16(0), 0, u16(entries.len), u16(entries.len)] { put16(mut output, value) }
	put32(mut output, u32(directory.len))
	put32(mut output, u32(start))
	put16(mut output, 0)
	return output
}

fn test_apk_manifest_extraction_unique_root_entry_crc_and_compression() {
	root := os.join_path(os.temp_dir(), 'vinix-account-manifest-' + rand.uuid_v4())
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	data := fixture(Fixture{})
	path := root + '/test.apk'
	for compress in [false, true] {
		mut archive := szip.open(path, if compress {
			szip.CompressionLevel.best_compression
		} else {
			szip.CompressionLevel.no_compression
		}, .write)!
		archive.open_entry('AndroidManifest.xml')!
		archive.write_entry(data)!
		archive.close_entry()
		archive.close()
		verify_activity(path, fixture_package, fixture_class)!
	}
	for entries in [
		[Entry{'AndroidManifest.xml', data}, Entry{'AndroidManifest.xml', data}],
		[Entry{'other/AndroidManifest.xml', data}],
		[Entry{'AndroidManifest.xml', '<manifest/>'.bytes()}],
	] {
		os.write_file_array(path, apk_fixture(entries, false))!
		mut denied := false
		verify_activity(path, fixture_package, fixture_class) or { denied = true }
		assert denied
	}
	os.write_file_array(path, apk_fixture([Entry{'AndroidManifest.xml', data}], false))!
	verify_activity(path, fixture_package, fixture_class)!
	os.write_file_array(path, apk_fixture([Entry{'AndroidManifest.xml', data}], true))!
	mut denied := false
	verify_activity(path, fixture_package, fixture_class) or { denied = true }
	assert denied
}
