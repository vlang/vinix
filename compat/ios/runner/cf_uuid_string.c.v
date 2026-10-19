// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct CFUUIDStringFailure {}
fn (_ &CFUUIDStringFailure) msg() string { return 'iOS: unsupported CFUUID string storage, allocator or runtime lifetime' }
fn (_ &CFUUIDStringFailure) code() int { return 1 }
__global cf_uuid_string_failure_value = CFUUIDStringFailure{}
fn cf_uuid_string_failure() IError { return unsafe { &cf_uuid_string_failure_value } }

fn cf_uuid_string_hex(unit u16) int {
	return if unit <= 0x7f { ns_uuid_hex(u8(unit)) } else { -1 }
}

// Native CFUUID parsing examines at most 100 UTF-16 units, skips leading
// non-hex units and consumes fixed separator slots. Bad/incomplete pairs are
// zero bytes; only an empty string returns nil. This differs from NSUUID.
fn cf_uuid_create_from_string_checked(allocator u64, string_object u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return cf_uuid_string_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if allocator != 0 && allocator != cf_allocator_default() { return cf_uuid_string_failure() }
	text := cf_string_compare_text(string_object) or { return cf_uuid_string_failure() }
	if text.len == 0 { return u64(0) }
	mut units := [100]u16{}
	mut length := 0
	mut cursor := CFStringCompareCursor{text: text}
	for length < 100 {
		unit := cursor.next()
		if unit == 0x10000 { break }
		units[length] = u16(unit)
		length++
	}
	mut position := 0
	for position < length && cf_uuid_string_hex(units[position]) < 0 { position++ }
	mut bytes := [16]u8{}
	for i in 0 .. 16 {
		if i in [4, 6, 8, 10]! { position++ }
		if position + 1 < length {
			hi := cf_uuid_string_hex(units[position])
			lo := cf_uuid_string_hex(units[position + 1])
			if hi >= 0 && lo >= 0 { bytes[i] = u8(hi * 16 + lo) }
		}
		position += 2
	}
	object := objc_allocate(ios_runtime.names['VinixCFUUID'])
	mut header := obj_header(object)
	unsafe { C.memcpy(&header.uuid_bytes[0], &bytes[0], 16) }
	return object
}

// Allocator/string in x0/x1; one owned opaque CFUUID reference in x0.
fn cf_uuid_create_from_string(allocator u64, string_object u64) u64 {
	return cf_uuid_create_from_string_checked(allocator, string_object) or { panic(err) }
}
