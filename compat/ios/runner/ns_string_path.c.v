// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn ns_string_last_path_component(object u64) u64 {
	// Keep the mutable/constant string borrow under the runtime lock. Allocate
	// the result after taking a snapshot: constructors may call application code.
	C.ios_objc_initialize_lock()
	source := cf_string_compare_text(object) or {
		C.ios_objc_initialize_unlock()
		panic('iOS: lastPathComponent requires a live UTF8 string')
	}
	text := source.clone()
	C.ios_objc_initialize_unlock()
	defer { unsafe { text.free() } }
	mut end := text.len
	for end > 1 && text[end - 1] == `/` { end-- }
	mut start := end
	for start > 0 && text[start - 1] != `/` { start-- }
	// Every nonempty all-slash path denotes root. Dots, tildes, backslashes,
	// embedded NULs and Unicode scalars are preserved without normalization.
	if start == end && end > 0 { start = 0 }
	component := unsafe { tos(text.str + start, end - start) }
	return objc_autorelease(owned_string(component))
}

fn ns_string_append_path_component(object u64, other u64) u64 {
	C.ios_objc_initialize_lock()
	left := mutable_string_source(object)
	right := mutable_string_source(other)
	// Foundation rejects NULs anywhere in either input, even in a component
	// that would otherwise be empty after separator normalization.
	if left.contains('\x00') || right.contains('\x00') {
		C.ios_objc_initialize_unlock()
		return 0
	}
	if u64(left.len) + u64(right.len) + 1 > mutable_string_limit {
		panic('iOS: path append exceeds the supported size')
	}
	mut joined := []u8{cap: left.len + right.len + 1}
	defer { unsafe { joined.free() } }
	for part in [left, right]! {
		if joined.len > 0 && joined[joined.len - 1] != `/` && part.len > 0 {
			joined << `/`
		}
		for byte in part {
			if byte == `/` && joined.len > 0 && joined[joined.len - 1] == `/` { continue }
			joined << byte
		}
	}
	if joined.len > 1 && joined[joined.len - 1] == `/` { joined.delete_last() }
	// The borrowed source bytes no longer participate after dropping the lock.
	// Construct an immutable, autoreleased result outside application callbacks.
	C.ios_objc_initialize_unlock()
	text := unsafe { tos(joined.data, joined.len) }
	return objc_autorelease(owned_string(text))
}
