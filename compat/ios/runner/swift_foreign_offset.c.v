// SPDX-License-Identifier: GPL-2.0-or-later
module main

// ARM64: index x0, signed UTF-8 byte distance x1, borrowed view x2/x3,
// returned raw String.Index x0. Zero distance is the measured exact no-op.
// Nonzero movement maps UTF-16/transcoding positions to byte positions and
// back in two linear scans, avoiding repeated successor scans or allocation.
fn swift_foreign_offset_checked(index u64, distance i64, first u64, second u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return swift_foreign_count_failure() }
	if distance == 0 { return index }
	if (index & 12) == 4 { return swift_foreign_count_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	length := swift_foreign_count_checked(first, second)!
	text := swift_foreign_count_text(second & swift_address_mask)!
	offset := index >> 16
	transcoded := (index >> 14) & 3
	mut start := -1
	mut byte := 0
	mut units := u64(0)
	for byte < text.len {
		lead := text[byte]
		width := if lead < 0x80 { 1 } else if lead < 0xe0 { 2 } else if lead < 0xf0 { 3 } else { 4 }
		unit_width := if width == 4 { u64(2) } else { u64(1) }
		if offset < units + unit_width {
			if offset != units {
				if distance < 0 || transcoded != 0 || index & 1 != 0 { return swift_foreign_count_failure() }
				start = byte // Measured forward alignment to the scalar start.
			} else {
				if transcoded >= u64(width) { return swift_foreign_count_failure() }
				start = byte + int(transcoded)
			}
			break
		}
		units += unit_width
		byte += width
	}
	if offset == (first & swift_count_mask) && transcoded == 0 { start = int(length) }
	if start < 0 || distance < -i64(start) || distance > length - i64(start) {
		return swift_foreign_count_failure() // Bounds precede addition, including INT64_MIN/MAX.
	}
	target := int(i64(start) + distance)
	byte = 0; units = 0
	for byte < text.len {
		lead := text[byte]
		width := if lead < 0x80 { 1 } else if lead < 0xe0 { 2 } else if lead < 0xf0 { 3 } else { 4 }
		if target < byte + width {
			flags := if distance > 0 && target == byte { u64(9) } else { u64(8) }
			return (units << 16) | (u64(target - byte) << 14) | flags
		}
		units += if width == 4 { u64(2) } else { u64(1) }
		byte += width
	}
	return (units << 16) | if distance > 0 { u64(9) } else { u64(8) }
}
fn swift_foreign_offset(index u64, distance i64, first u64, second u64) u64 {
	return swift_foreign_offset_checked(index, distance, first, second) or { panic(err) }
}
