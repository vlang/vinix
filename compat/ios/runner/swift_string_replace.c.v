// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8

struct SwiftStringReplaceFailure {}
fn (_ &SwiftStringReplaceFailure) msg() string { return 'iOS: unsupported Swift String replacement' }
fn (_ &SwiftStringReplaceFailure) code() int { return 1 }
__global swift_string_replace_failure_value = SwiftStringReplaceFailure{}
fn swift_string_replace_failure() IError { return unsafe { &swift_string_replace_failure_value } }

// Under the recursive registry lock. The Swift caller owns the readable
// two-word value and any immutable literal span until this call returns.
// Validate mortal owners before accessing their storage; foreign NSStrings use
// the existing checked UTF-16/UTF-8 extent. Shared/custom storage is separate.
fn swift_replace_bytes(value u64, scratch u64) !SwiftStringBytes {
	if value == 0 || value & 7 != 0 { return swift_string_replace_failure() }
	words := unsafe { *(&SwiftStringWords(value)) }
	mut bytes := SwiftStringBytes{}
	if words.second & (u64(1) << 61) != 0 {
		if words.second & (u64(1) << 63) == 0 || words.second & (u64(1) << 60) != 0 { return swift_string_replace_failure() }
		unsafe { *(&SwiftStringWords(scratch)) = words }
		bytes = SwiftStringBytes{scratch, (words.second >> 56) & 15}
	} else if words.second & (u64(1) << 60) != 0 {
		count := swift_foreign_count_checked(words.first, words.second)!
		text := swift_foreign_count_text(words.second & swift_address_mask)!
		bytes = SwiftStringBytes{u64(text.str), u64(count)}
	} else {
		count := words.first & swift_count_mask
		owner := words.second & swift_address_mask
		if words.first & (u64(1) << 60) == 0 || owner == 0 || count > 1048576
			|| owner > ~u64(0) - 32 - count { return swift_string_replace_failure() }
		if words.second & (u64(1) << 63) == 0 {
			capacity := ios_runtime.swift_strings[owner] or { return swift_string_replace_failure() }
			if count > capacity { return swift_string_replace_failure() }
		}
		bytes = SwiftStringBytes{owner + 32, count}
	}
	if bytes.count > 1048576 || !utf8.validate_str(unsafe { tos(&u8(bytes.address), int(bytes.count)) }) { return swift_string_replace_failure() }
	return bytes
}

fn swift_replace_ascii(bytes SwiftStringBytes) bool {
	for i in u64(0) .. bytes.count { if unsafe { *(&u8(bytes.address + i)) } >= 128 { return false } }
	return true
}

// KMP finds nonoverlapping, left-to-right matches in linear time. Use the same
// pass to measure and fill, bounded by the output cap before any output write.
// Every span is length-delimited, including embedded NULs and suffixes.
fn swift_replace_pass(source SwiftStringBytes, needle SwiftStringBytes, replacement SwiftStringBytes, prefix u64, output u64, capacity u64) !u64 {
	mut matched := u64(0)
	mut start := u64(0)
	mut length := u64(0)
	for i in u64(0) .. source.count {
		if needle.count == 0 { break }
		byte := unsafe { *(&u8(source.address + i)) }
		for matched > 0 && byte != unsafe { *(&u8(needle.address + matched)) } { matched = read64(prefix + (matched - 1) * 8) }
		if byte == unsafe { *(&u8(needle.address + matched)) } { matched++ }
		if matched != needle.count { continue }
		span := i + 1 - needle.count - start
		if span > capacity - length || replacement.count > capacity - length - span { return swift_string_replace_failure() }
		if output != 0 {
			C.memcpy(voidptr(output + length), voidptr(source.address + start), usize(span))
			C.memcpy(voidptr(output + length + span), voidptr(replacement.address), usize(replacement.count))
		}
		length += span + replacement.count
		start = i + 1
		matched = 0
	}
	span := source.count - start
	if span > capacity - length { return swift_string_replace_failure() }
	if output != 0 { C.memcpy(voidptr(output + length), voidptr(source.address + start), usize(span)) }
	return length + span
}

fn swift_string_replace_checked(frame u64) !SwiftStringWords {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return swift_string_replace_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	// x0/x1 borrowed pattern/replacement, x2 options, x3/x4 Range payload,
	// low byte of x5 Optional tag; x6/x7 Self/Pattern metadata. Stack words
	// are Replacement metadata, then the three StringProtocol tables. Self is
	// borrowed indirectly in x20. These concrete String operations need no
	// generic callbacks or witness reads. Return an owned String in x0/x1.
	metadata := swift_string_metadata()
	if read64(frame + 48) != metadata || read64(frame + 56) != metadata
		|| read64(frame + 72) != metadata || read64(frame + 40) & 255 != 1
		|| read64(frame + 16) !in [u64(0), 2]! { return swift_string_replace_failure() }
	scratch := u64(C.__builtin_alloca(48))
	source := swift_replace_bytes(read64(frame + 64), scratch)!
	needle := swift_replace_bytes(read64(frame), scratch + 16)!
	replacement := swift_replace_bytes(read64(frame + 8), scratch + 32)!
	if needle.count > 4096 { return swift_string_replace_failure() }
	// Default Foundation search observes canonical equivalence. Byte search
	// implements that contract for ASCII source/pattern only. Literal search
	// additionally accepts validated Unicode. Do not silently approximate the
	// default Unicode, case/diacritic folding, regex or explicit-range paths.
	if read64(frame + 16) == 0 && (!swift_replace_ascii(source) || !swift_replace_ascii(needle)) { return swift_string_replace_failure() }
	prefix := u64(C.calloc(usize(needle.count + 1), 8))
	if prefix == 0 { return swift_string_replace_failure() }
	defer { C.free(voidptr(prefix)) }
	mut matched := u64(0)
	for i in u64(1) .. needle.count {
		byte := unsafe { *(&u8(needle.address + i)) }
		for matched > 0 && byte != unsafe { *(&u8(needle.address + matched)) } { matched = read64(prefix + (matched - 1) * 8) }
		if byte == unsafe { *(&u8(needle.address + matched)) } { matched++ }
		unsafe { *(&u64(prefix + i * 8)) = matched }
	}
	length := swift_replace_pass(source, needle, replacement, prefix, 0, 1048576)!
	output := u64(C.malloc(usize(length + 1)))
	if output == 0 { return swift_string_replace_failure() }
	defer { C.free(voidptr(output)) }
	if swift_replace_pass(source, needle, replacement, prefix, output, length)! != length { return swift_string_replace_failure() }
	destination := u64(C.__builtin_alloca(16))
	unsafe { *(&SwiftStringWords(destination)) = SwiftStringWords{second: u64(0xe000000000000000)} }
	swift_string_append_bytes(destination, output, length)
	return unsafe { *(&SwiftStringWords(destination)) }
}
fn swift_string_replace(frame u64) SwiftStringWords { return swift_string_replace_checked(frame) or { panic(err) } }
