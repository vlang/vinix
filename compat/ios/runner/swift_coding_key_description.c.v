// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8

type SwiftCodingKeyGetter = fn (u64, u64, u64, u64) SwiftStringWords

// Native uses the unqualified nominal name, even for nested CodingKeys.
// Accept canonical scalars and file-backed nongeneric struct/enum records.
// Classes, generic names and dynamic/foreign metadata need separate support.
fn swift_coding_key_name(metadata u64) !string {
	page := u64(C.getpagesize())
	if ios_runtime.swift_integer_arena != 0 && metadata == ios_runtime.swift_integer_arena + page + 16 { return 'Int' }
	if ios_runtime.swift_bool_metadata_arena != 0 && metadata == ios_runtime.swift_bool_metadata_arena + page + 16 { return 'Bool' }
	if ios_runtime.swift_merge_error_metadata_arena != 0 && metadata == ios_runtime.swift_merge_error_metadata_arena + page + 16 { return '_MergeError' }
	if metadata & 7 != 0 || !swift_print_image_range(metadata, 16) { return swift_describing_failure() }
	kind := read64(metadata)
	if kind !in [u64(0x200), 0x201]! { return swift_describing_failure() }
	descriptor := read64(metadata + 8)
	if descriptor & 3 != 0 || !swift_print_image_range(descriptor, 20)
		|| read32(descriptor) != if kind == 0x200 { u32(0x51) } else { u32(0x52) } {
		return swift_describing_failure()
	}
	name := swift_print_image_text(swift_print_relative(descriptor + 8)!)!
	if name.len == 0 || !utf8.validate_str(name) { return swift_describing_failure() }
	return name
}

// Self is borrowed; the supplied CodingKey table owns the getter semantics.
// intValue (slot 40) is called before stringValue (slot 24). The latter
// returns an owned String, released on success and every checked failure.
// No registry lock spans either callback, so witnesses may reenter or join
// another runtime worker. Only the final text allocation outlives this call.
fn swift_coding_key_description_checked(metadata u64, table u64, source u64) !SwiftStringWords {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| table == 0 || table & 7 != 0 || table > ~u64(0) - 47 || source == 0 {
		return swift_describing_failure()
	}
	name := swift_coding_key_name(metadata)!
	call := unsafe { SwiftCodingKeyGetter(voidptr(swift_hash_entry(1856))) }
	integer_entry := read64(table + 40)
	if integer_entry == 0 { return swift_describing_failure() }
	number := call(metadata, table, source, integer_entry)
	if number.second & 255 > 1 { return swift_describing_failure() }
	mut digits := [32]u8{}
	mut count := i32(3)
	if number.second & 255 == 0 {
		count = unsafe { C.snprintf(&char(&digits[0]), 32, c'%lld', i64(number.first)) }
		if count < 1 || count >= 32 { return swift_describing_failure() }
	} else { unsafe { C.memcpy(&digits[0], c'nil', 3) } }
	string_entry := read64(table + 24)
	if string_entry == 0 { return swift_describing_failure() }
	words := call(metadata, table, source, string_entry)
	defer { swift_bridge_release(words.second) }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	scratch := u64(C.__builtin_alloca(32))
	unsafe { *(&SwiftStringWords(scratch)) = words }
	bytes := swift_replace_bytes(scratch, scratch + 16)!
	// The complete output, including the name and punctuation, is bounded.
	length := u64(name.len) + bytes.count + u64(count) + 29
	if length > 1048576 { return swift_describing_failure() }
	output := u64(C.__builtin_alloca(16))
	unsafe { *(&SwiftStringWords(output)) = swift_interpolation_init(i64(length), 0) }
	for part in [SwiftStringBytes{u64(name.str), u64(name.len)},
		SwiftStringBytes{u64(c'(stringValue: "'), 15}, bytes,
		SwiftStringBytes{u64(c'", intValue: '), 13},
		SwiftStringBytes{u64(unsafe { &digits[0] }), u64(count)},
		SwiftStringBytes{u64(')'.str), 1}]! {
		swift_string_append_bytes(output, part.address, part.count)
	}
	return unsafe { *(&SwiftStringWords(output)) }
}

fn swift_coding_key_description(metadata u64, table u64, source u64) SwiftStringWords {
	return swift_coding_key_description_checked(metadata, table, source) or { panic(err) }
}

fn swift_coding_key_description_emit(code u64) {
	write32(code, 0xaa1403e2) // Swift x20 -> C third argument.
	write32(code + 4, 0x58000070)
	write32(code + 8, 0xd61f0200)
	unsafe { *(&u64(code + 16)) = u64(voidptr(swift_coding_key_description)) }
	// C(metadata,table,Self,entry) -> Swift getter, retaining x0/x1 arguments.
	for i, op in [u32(0xa9be7bfd), 0xa90153f3, 0xaa0203f4, 0xd63f0060,
		0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! { write32(code + 32 + u64(i * 4), op) }
}

fn swift_coding_key_description_symbol(symbol string) ?u64 {
	if symbol != '_$ss9CodingKeyPsE11descriptionSSvg' || ios_runtime == unsafe { nil }
		|| ios_runtime.swift_concurrency_retired { return none }
	return swift_hash_entry(1824)
}
