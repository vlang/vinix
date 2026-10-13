// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8

struct SwiftForeignCountFailure {}
fn (_ &SwiftForeignCountFailure) msg() string { return 'iOS: unsupported or invalid foreign Swift UTF8View' }
fn (_ &SwiftForeignCountFailure) code() int { return 1 }
__global swift_foreign_count_failure_value = SwiftForeignCountFailure{}
fn swift_foreign_count_failure() IError { return unsafe { &swift_foreign_count_failure_value } }

// Borrow text under the registry lock, validating the owner before any isa or
// field read. UTF-16 constants use the loader's existing decoded UTF-8 cache.
fn swift_foreign_count_text(owner u64) !string {
	if owner !in ios_runtime.objects && owner !in ios_runtime.constants { return swift_foreign_count_failure() }
	if !objc_is_kind(owner, ios_runtime.names['NSString']) { return swift_foreign_count_failure() }
	if header := ios_runtime.objects[owner] {
		if C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.text_length < 0
			|| header.text_length > 1048576 || (header.text_length != 0 && header.text == unsafe { nil }) {
			return swift_foreign_count_failure()
		}
		if header.text_length == 0 { return '' }
		return string_text(owner)
	}
	flags := read32(owner + 8)
	if flags == 0x7d0 {
		text := ios_runtime.constant_utf8[owner] or { return swift_foreign_count_failure() }
		if text.len > 1048576 { return swift_foreign_count_failure() }
		return text
	}
	if flags != 0x7c8 || read64(owner + 24) > 1048576 { return swift_foreign_count_failure() }
	if read64(owner + 24) == 0 { return '' }
	if read64(owner + 16) == 0 { return swift_foreign_count_failure() }
	return string_text(owner)
}

// Measured ARM64 ABI: the borrowed UTF8View occupies x0/x1, with its UTF-16
// code-unit count in the first word and NSString address in the second. The
// signed UTF-8 byte count returns in x0. This is the foreign-only fallback;
// native/inline views, shared storage and foreign UTF-8 indexing are separate.
fn swift_foreign_count_checked(first u64, second u64) !i64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return swift_foreign_count_failure() }
	discriminator := second >> 60
	if (discriminator != 5 && discriminator != 13)
		|| first & ~(swift_count_mask | u64(0xc000000000000000)) != 0 { return swift_foreign_count_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	text := swift_foreign_count_text(second & swift_address_mask)!
	if !utf8.validate_str(text) { return swift_foreign_count_failure() }
	mut units := u64(0)
	for byte in text {
		if byte & 0xc0 != 0x80 { units += if byte >= 0xf0 { u64(2) } else { u64(1) } }
	}
	if units != (first & swift_count_mask) { return swift_foreign_count_failure() }
	return i64(text.len)
}
fn swift_foreign_count(first u64, second u64) i64 {
	return swift_foreign_count_checked(first, second) or { panic(err) }
}
