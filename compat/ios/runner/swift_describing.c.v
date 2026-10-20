// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftDescribingFailure {}
fn (_ &SwiftDescribingFailure) msg() string { return 'iOS: unsupported or invalid Swift describing value' }
fn (_ &SwiftDescribingFailure) code() int { return 1 }
__global swift_describing_failure_value = SwiftDescribingFailure{}
fn swift_describing_failure() IError { return unsafe { &swift_describing_failure_value } }

// The special Error existential is one owned object word on Darwin. Its
// metadata has one Error protocol and the measured 0x81000001 flags. Vinix
// currently supplies this layout for its concrete CFError owners only, using
// the existing ObjC reference witnesses and the existing sealed error arena.
fn swift_error_existential_metadata() u64 {
	return swift_error_metadata_arena() + u64(C.getpagesize()) + 392
}

// Called with the registry lock held. Return borrowed text only after checking
// its registered owner and bound; malformed fields cannot reach the copier.
fn swift_describing_text(owner u64) !string {
	header := ios_runtime.objects[owner] or { return swift_describing_failure() }
	if !objc_is_kind(owner, ios_runtime.names['NSString']) || header.text_length > 1048576
		|| (header.text_length != 0 && header.text == unsafe { nil }) { return swift_describing_failure() }
	return string_text(owner)
}

fn swift_describing_error(owner u64) !SwiftStringWords {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[owner] or { return swift_describing_failure() }
	if header.cls != cf_error_type_id() || C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 {
		return swift_describing_failure()
	}
	domain := swift_describing_text(header.fields[0])!
	mut description := '(null)'
	mut suffix := false
	if header.fields[1] != 0 {
		info := ios_runtime.objects[header.fields[1]] or { return swift_describing_failure() }
		if info.cf_raw_values || !objc_is_kind(header.fields[1], ios_runtime.names['NSDictionary'])
			|| info.keys.len != info.items.len || info.keys.len > 1 { return swift_describing_failure() }
		if info.keys.len == 1 {
			if swift_describing_text(info.keys[0])! != 'NSLocalizedDescription' { return swift_describing_failure() }
			description = swift_describing_text(info.items[0])!
			suffix = true
		}
	}
	mut number := [32]u8{}
	length := unsafe { C.snprintf(&char(&number[0]), 32, c'%lld', header.number) }
	if length < 1 || length >= 32 { return swift_describing_failure() }
	code := unsafe { (&u8(&number[0])).vstring_with_len(int(length)) }
	parts := ['Error Domain=', domain, ' Code=', code, ' "', description, '"',
		if suffix { ' UserInfo={NSLocalizedDescription=' } else { '' },
		if suffix { description } else { '' }, if suffix { '}' } else { '' }]!
	mut count := 0
	for part in parts { if part.len > 1048576 - count { return swift_describing_failure() }; count += part.len }
	words := unsafe { &SwiftStringWords(C.__builtin_alloca(16)) }
	unsafe { *words = swift_interpolation_init(i64(count), 0) }
	for part in parts { swift_string_append_bytes(u64(words), u64(part.str), u64(part.len)) }
	return unsafe { *words }
}

// String.init(describing:) consumes an indirect value in x0, with its type
// metadata in x1, and returns an owned String in x0/x1. Select only canonical
// metadata already published by this runtime before inspecting the value.
// General reflection, Swift error boxes and arbitrary conformances require
// separate support and are rejected without consuming a failed checked call.
fn swift_string_describing_checked(source u64, metadata u64) !SwiftStringWords {
	page := u64(C.getpagesize())
	C.ios_objc_initialize_lock()
	mut kind := 0
	if metadata != 0 {
		if ios_runtime.swift_metadata_arena != 0 && metadata == ios_runtime.swift_metadata_arena + page + 16 { kind = 1 }
		else if ios_runtime.swift_integer_arena != 0 && metadata == ios_runtime.swift_integer_arena + page + 16 { kind = 2 }
		else if ios_runtime.swift_void_arena != 0 && metadata == ios_runtime.swift_void_arena + 8 { kind = 3 }
		else if ios_runtime.swift_error_arena != 0 && metadata == ios_runtime.swift_error_arena + page + 392 { kind = 4 }
		else if metadata == (ios_runtime.swift_objc_metadata[cf_error_type_id()] or { u64(0) }) { kind = 4 }
	}
	C.ios_objc_initialize_unlock()
	if kind == 0 { return swift_describing_failure() }
	if kind == 3 { return swift_string_literal(c'()', 2, true) }
	if source == 0 || source & 7 != 0 || source > ~u64(0) - 15 { return swift_describing_failure() }
	if kind == 1 { return unsafe { *(&SwiftStringWords(source)) } } // Transfer, no retain or scratch owner.
	if kind == 2 {
		return swift_integer_description_checked(i64(read64(source)))
	}
	owner := read64(source)
	result := swift_describing_error(owner)!
	// Copy all borrowed error text before retiring the consumed input. Release
	// outside the registry lock so that deallocation may reenter the runtime.
	objc_release(owner)
	return result
}

fn swift_string_describing(source u64, metadata u64) SwiftStringWords {
	return swift_string_describing_checked(source, metadata) or { panic(err) }
}
