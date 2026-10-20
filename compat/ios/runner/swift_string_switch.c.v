// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftStringSwitchFailure {}
fn (_ &SwiftStringSwitchFailure) msg() string { return 'iOS: invalid or unsupported Swift String switch table/value' }
fn (_ &SwiftStringSwitchFailure) code() int { return 1 }
__global swift_string_switch_failure_value = SwiftStringSwitchFailure{}
fn swift_string_switch_failure() IError { return unsafe { &swift_string_switch_failure_value } }

// Caller holds the registry lock. Array<StaticString> has a 32-byte header
// and 24-byte element stride, with only 17 initialized bytes per element.
// Accept our typed owners or file-backed loaded-image tables, without reading
// arbitrary owners, class metadata, refcounts or a static initialization token.
fn swift_string_switch_count(owner u64) !u64 {
	if owner == 0 || owner & 7 != 0 || owner > ~u64(0) - 32 { return swift_string_switch_failure() }
	if owner == ios_runtime.swift_empty_array { return 0 }
	mut count := u64(0)
	if storage := ios_runtime.swift_arrays[owner] {
		if ios_runtime.swift_static_string_metadata_retired
			|| ios_runtime.swift_static_string_metadata_arena == 0
			|| storage.element != ios_runtime.swift_static_string_metadata_arena + u64(C.getpagesize()) + 16
			|| storage.tail != 32 || storage.stride != 24 { return swift_string_switch_failure() }
		count = read64(owner + 16)
		if count > storage.capacity { return swift_string_switch_failure() }
	} else {
		if !swift_print_image_range(owner + 16, 8) { return swift_string_switch_failure() }
		count = read64(owner + 16)
		if count != 0 && (count > 4096 || !swift_print_image_range(owner + 32, (count - 1) * 24 + 17)) {
			return swift_string_switch_failure()
		}
	}
	if count > 4096 || (count != 0 && owner > ~u64(0) - 32 - (count - 1) * 24 - 16) {
		return swift_string_switch_failure()
	}
	return count
}

// This compiler intrinsic requires pointer StaticStrings, as native utf8Start
// does; scalar StaticStrings are not case-table entries. Padding is never read.
fn swift_string_switch_case(row u64) !SwiftStringWords {
	data := read64(row)
	count := read64(row + 8)
	flags := unsafe { *(&u8(row + 16)) }
	if flags !in [u8(0), 2]! || data == 0 || count > 1048576 || data > ~u64(0) - count {
		return swift_string_switch_failure()
	}
	// Borrow the literal through the existing checked String reader/equality.
	return swift_string_literal(unsafe { &u8(data) }, i64(count), flags & 2 != 0)
}

// Measured ARM64: borrowed Array owner x0, String words x1/x2, signed Int x0.
// First canonical-equal case wins, including unequal UTF-8 byte counts and NULs.
// The existing equality helper frees its NFC temporaries. No table cache or ARC
// mutation is needed; registered owners stay borrowed under the recursive lock.
fn swift_string_switch_checked(owner u64, first u64, second u64) !i64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return swift_string_switch_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	count := swift_string_switch_count(owner)!
	if count == 0 { return -1 } // Native ignores the String for an empty table.
	values := u64(C.__builtin_alloca(32))
	unsafe { *(&SwiftStringWords(values)) = SwiftStringWords{first, second} }
	scratch := u64(C.__builtin_alloca(16))
	swift_string_hashable_bytes(values, scratch)! // Validate even a miss.
	mut total := u64(0)
	for i in u64(0) .. count {
		row := owner + 32 + i * 24
		length := read64(row + 8)
		if length > 16777216 - total { return swift_string_switch_failure() }
		total += length
		candidate := swift_string_switch_case(row)!
		unsafe { *(&SwiftStringWords(values + 16)) = candidate }
		if swift_string_hashable_equal_checked(values, values + 16)! { return i64(i) }
	}
	return -1
}

fn swift_string_switch(owner u64, first u64, second u64) i64 {
	return swift_string_switch_checked(owner, first, second) or { panic(err) }
}

fn swift_string_switch_symbol(symbol string) ?u64 {
	if symbol != '_$ss21_findStringSwitchCase5cases6stringSiSays06StaticB0VG_SStF'
		|| ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return none }
	return u64(unsafe { voidptr(swift_string_switch) })
}
