// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8

// _StringGuts.grow takes a total UTF-8 capacity, and always replaces the
// representation with unique native storage. Unlike reserveCapacity, this
// entry point does not skip small or already sufficient capacities.
fn swift_string_grow_checked(requested i64, destination u64) ! {
	if destination == 0 || destination & 7 != 0 {
		return error('Swift String grow requires aligned inout storage')
	}
	if requested > i64(swift_count_mask) {
		return error('Swift String grow capacity exceeds the supported count')
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	previous := unsafe { *(&SwiftStringWords(destination)) }
	mut scratch := [u64(0), 0]!
	mut bytes := SwiftStringBytes{}
	mut old_capacity := u64(0)
	mut unique := false
	if previous.second & (u64(1) << 61) != 0 {
		bytes = swift_string_bytes(previous, u64(unsafe { &scratch[0] }))!
	} else if previous.second & (u64(1) << 60) != 0 {
		count := swift_foreign_count_checked(previous.first, previous.second)!
		text := swift_foreign_count_text(previous.second & swift_address_mask)!
		bytes = SwiftStringBytes{u64(text.str), u64(count)}
	} else {
		owner := previous.second & swift_address_mask
		count := previous.first & swift_count_mask
		if previous.second >> 60 !in [u64(0), 8]! || previous.first & (u64(1) << 60) == 0
			|| owner == 0 || owner > ~u64(0) - 32 - count {
			return error('Swift String grow storage is not supported')
		}
		if previous.second & (u64(1) << 63) == 0 {
			old_capacity = ios_runtime.swift_strings[owner] or {
				return error('Swift String grow requires a registered native owner')
			}
			if count > old_capacity || read64(owner + 16) != old_capacity + 1
				|| read64(owner + 24) != previous.first {
				return error('Swift String grow native storage is inconsistent')
			}
			unique = swift_buffer_refs(owner, 0)! == 1
		}
		bytes = SwiftStringBytes{owner + 32, count}
	}
	text := unsafe { (&u8(bytes.address)).vstring_with_len(int(bytes.count)) }
	if !utf8.validate_str(text) {
		return error('Swift String grow requires valid UTF-8')
	}
	mut capacity := if requested > 0 { u64(requested) } else { u64(0) }
	if unique {
		// The native runtime applies 1.625x geometric growth only to unique
		// native storage. A retained alias must not carry its spare capacity
		// into the new copy.
		growth := old_capacity + (old_capacity >> 1) + (old_capacity >> 3)
		if growth > swift_count_mask {
			return error('Swift String grow geometric capacity exceeds the supported count')
		}
		if capacity < growth { capacity = growth }
	}
	if capacity < bytes.count { capacity = bytes.count }
	mut ascii := true
	for i in u64(0) .. bytes.count {
		if unsafe { *(&u8(bytes.address + i)) } >= 128 { ascii = false }
	}
	result := swift_string_storage(capacity, bytes.count, ascii)
	if bytes.count != 0 {
		C.memcpy(unsafe { voidptr(result.second + 32) }, unsafe { voidptr(bytes.address) }, usize(bytes.count))
	}
	// calloc supplies the trailing NUL, including empty Strings. Publish
	// before releasing the old owner: the source bytes may belong to it.
	unsafe { *(&SwiftStringWords(destination)) = result }
	swift_bridge_release(previous.second)
}

fn swift_string_grow(requested i64, destination u64) {
	swift_string_grow_checked(requested, destination) or { panic('iOS: ${err}') }
}
