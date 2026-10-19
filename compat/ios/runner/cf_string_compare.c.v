// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8

struct CFStringCompareFailure {}
fn (_ &CFStringCompareFailure) msg() string { return 'iOS: unsupported or invalid CFString comparison' }
fn (_ &CFStringCompareFailure) code() int { return 1 }
__global cf_string_compare_failure_value = CFStringCompareFailure{}
fn cf_string_compare_failure() IError { return unsafe { &cf_string_compare_failure_value } }

// Caller holds the runtime lock. Validate provenance before reading an isa or
// borrowing bytes; UTF-16 image constants use the loader's decoded UTF-8 cache.
fn cf_string_compare_text(object u64) !string {
	if object !in ios_runtime.objects && object !in ios_runtime.constants { return cf_string_compare_failure() }
	if !objc_is_kind(object, ios_runtime.names['NSString']) { return cf_string_compare_failure() }
	if header := ios_runtime.objects[object] {
		if header.destroyed || C.ios_ref_change(unsafe { &header.refs }, 0) <= 0
			|| header.text_length < 0 || header.text_length > 16777216
			|| (header.text_length != 0 && header.text == unsafe { nil }) { return cf_string_compare_failure() }
		if header.text_length == 0 { return '' }
	} else {
		flags := read32(object + 8)
		if flags == 0x7d0 {
			if object !in ios_runtime.constant_utf8 { return cf_string_compare_failure() }
		} else if flags != 0x7c8 || read64(object + 24) > 16777216
			|| (read64(object + 24) != 0 && read64(object + 16) == 0) { return cf_string_compare_failure() }
		if flags == 0x7c8 && read64(object + 24) == 0 { return '' }
	}
	text := string_text(object)
	if text.len > 16777216 || !utf8.validate_str(text) { return cf_string_compare_failure() }
	return text
}

struct CFStringCompareCursor {
mut:
	text string
	offset int
	pending u16
}

// Stream UTF-16 units from validated UTF-8 without a temporary conversion.
// 0x10000 is an end marker, distinct from every unit including embedded NUL.
fn (mut cursor CFStringCompareCursor) next() u32 {
	if cursor.pending != 0 {
		unit := cursor.pending
		cursor.pending = 0
		return u32(unit)
	}
	if cursor.offset == cursor.text.len { return 0x10000 }
	first := cursor.text[cursor.offset]
	cursor.offset++
	if first < 0x80 { return u32(first) }
	width := if first < 0xe0 { 2 } else if first < 0xf0 { 3 } else { 4 }
	mut scalar := u32(first & if width == 2 { u8(0x1f) } else if width == 3 { u8(0x0f) } else { u8(7) })
	for _ in 1 .. width {
		scalar = scalar << 6 | u32(cursor.text[cursor.offset] & 0x3f)
		cursor.offset++
	}
	if width != 4 { return scalar }
	scalar -= 0x10000
	cursor.pending = u16(0xdc00 | (scalar & 0x3ff))
	return 0xd800 | (scalar >> 10)
}

fn cf_string_compare_checked(left u64, right u64, options u64) !i64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired || options != 0 { return cf_string_compare_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	a := cf_string_compare_text(left)!
	b := cf_string_compare_text(right)!
	mut first := CFStringCompareCursor{text: a}
	mut second := CFStringCompareCursor{text: b}
	for {
		x := first.next()
		y := second.next()
		if x == 0x10000 { return if y == 0x10000 { i64(0) } else { i64(-1) } }
		if y == 0x10000 || x > y { return i64(1) }
		if x < y { return i64(-1) }
	}
	return i64(0)
}

// CFComparisonResult is signed long on ARM64; options occupies all of x2.
fn cf_string_compare(left u64, right u64, options u64) i64 {
	return cf_string_compare_checked(left, right, options) or { panic(err) }
}
