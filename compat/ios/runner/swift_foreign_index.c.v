// SPDX-License-Identifier: GPL-2.0-or-later
module main

// ARM64: index x0, borrowed UTF8View x1/x2, returned String.Index x0.
// Index bits 16..63 hold the UTF-16 offset; bits 14..15 hold the UTF-8
// position within that scalar. Native successor flags are 8 within a scalar
// and 9 at its next boundary. An unmarked UTF-16 surrogate interior aligns
// to its scalar start before advancing, as measured against libswiftCore.
fn swift_foreign_index_after_checked(index u64, first u64, second u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return swift_foreign_count_failure()
	}
	if (index & 12) == 4 { return swift_foreign_count_failure() } // Requires matching UTF-16 encoding.
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	// The existing checked view validates flags, UTF-8 and the complete UTF-16
	// extent. Its recursive lock cannot release the outer borrow held here.
	swift_foreign_count_checked(first, second)!
	text := swift_foreign_count_text(second & swift_address_mask)!
	offset := index >> 16
	transcoded := (index >> 14) & 3
	if offset >= (first & swift_count_mask) { return swift_foreign_count_failure() }
	mut units := u64(0)
	mut byte := 0
	for byte < text.len {
		lead := text[byte]
		width := if lead < 0x80 { 1 } else if lead < 0xe0 { 2 } else if lead < 0xf0 { 3 } else { 4 }
		unit_width := if width == 4 { u64(2) } else { u64(1) }
		if offset < units + unit_width {
			if offset != units && (index & 1 != 0 || transcoded != 0) {
				return swift_foreign_count_failure()
			}
			if transcoded >= u64(width) { return swift_foreign_count_failure() }
			if transcoded + 1 < u64(width) { return (units << 16) | ((transcoded + 1) << 14) | 8 }
			return ((units + unit_width) << 16) | 9
		}
		units += unit_width
		byte += width
	}
	return swift_foreign_count_failure()
}
fn swift_foreign_index_after(index u64, first u64, second u64) u64 {
	return swift_foreign_index_after_checked(index, first, second) or { panic(err) }
}
