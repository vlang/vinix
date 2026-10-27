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
