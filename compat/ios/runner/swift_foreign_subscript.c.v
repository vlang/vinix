// SPDX-License-Identifier: GPL-2.0-or-later
module main

// ARM64: index x0, borrowed UTF8View x1/x2, UInt8 in the low byte of w0.
// Read the registered UTF-16-indexed NSString/constant's existing UTF-8 bytes
// under the registry lock; no ownership transfer, scratch or scalar encoding.
fn swift_foreign_subscript_checked(index u64, first u64, second u64) !u32 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| (index & 12) == 4 { return swift_foreign_count_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	swift_foreign_count_checked(first, second)!
	text := swift_foreign_count_text(second & swift_address_mask)!
	offset := index >> 16
	transcoded := (index >> 14) & 3
	if offset >= (first & swift_count_mask) { return swift_foreign_count_failure() }
	mut byte := 0
	mut units := u64(0)
	for byte < text.len {
		lead := text[byte]
		width := if lead < 0x80 { 1 } else if lead < 0xe0 { 2 } else if lead < 0xf0 { 3 } else { 4 }
		unit_width := if width == 4 { u64(2) } else { u64(1) }
		if offset < units + unit_width {
			// This helper accepts scalar starts and UTF-8 transcoding positions.
			// UTF-16 surrogate interiors are outside the supported index subset.
			if offset != units || transcoded >= u64(width) { return swift_foreign_count_failure() }
			return u32(text[byte + int(transcoded)])
		}
		units += unit_width
		byte += width
	}
	return swift_foreign_count_failure()
}
fn swift_foreign_subscript(index u64, first u64, second u64) u32 {
	return swift_foreign_subscript_checked(index, first, second) or { panic(err) }
}
