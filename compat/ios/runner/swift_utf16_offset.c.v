// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8

// ARM64: index x0, signed UTF-16 distance x1, borrowed view x2/x3,
// raw String.Index result x0. Foreign storage uses UTF-16 encoded offsets;
// native storage uses UTF-8 offsets and one transcoding unit inside a pair.
// The recursive registry lock protects mortal storage for the entire borrow.
fn swift_utf16_offset_checked(index u64, distance i64, first u64, second u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return swift_foreign_count_failure()
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	offset := index >> 16
	transcoded := (index >> 14) & 3
	if second & (u64(1) << 60) != 0 {
		if (index & 12) == 4 { return swift_foreign_count_failure() }
		swift_foreign_count_checked(first, second)!
		count := i64(first & swift_count_mask)
		if offset > u64(count) || (offset == u64(count) && transcoded != 0)
			|| distance < -i64(offset) || distance > count - i64(offset) {
			return swift_foreign_count_failure()
		}
		return (u64(i64(offset) + distance) << 16) | 8
	}
	// Cross-encoding repair and shared/native non-tail storage are separate
	// helpers. Reject those forms before treating an encoded offset as bytes.
	if (index & 12) == 8 { return swift_foreign_count_failure() }
	mut inline := SwiftStringWords{ first: first, second: second }
	mut count := (second >> 56) & 15
	mut address := u64(unsafe { &inline })
	if second & (u64(1) << 61) != 0 {
		if second & (u64(1) << 63) == 0 { return swift_foreign_count_failure() }
	} else {
		count = first & swift_count_mask
		owner := second & swift_address_mask
		if first & (u64(1) << 60) == 0 || owner == 0 || count > 1024 * 1024 {
			return swift_foreign_count_failure()
		}
		if second & (u64(1) << 63) == 0 {
			capacity := ios_runtime.swift_strings[owner] or { return swift_foreign_count_failure() }
			if count > capacity { return swift_foreign_count_failure() }
		}
		address = owner + 32
	}
	text := unsafe { tos(&u8(address), int(count)) }
	if !utf8.validate_str(text) || offset > count || (offset == count && transcoded != 0) {
		return swift_foreign_count_failure()
	}
	ascii := if second & (u64(1) << 61) != 0 {
		second & (u64(1) << 62) != 0
	} else { first & (u64(1) << 63) != 0 }
	if ascii {
		for byte in text { if byte >= 128 { return swift_foreign_count_failure() } }
		if transcoded != 0 || distance < -i64(offset) || distance > i64(count - offset) {
			return swift_foreign_count_failure()
		}
		return (u64(i64(offset) + distance) << 16) | 13
	}
	mut byte := u64(0)
	mut units := i64(0)
	mut start := i64(-1)
	mut aligned := index
	for byte < count {
		lead := text[int(byte)]
		width := if lead < 0x80 { u64(1) } else if lead < 0xe0 { u64(2) } else if lead < 0xf0 { u64(3) } else { u64(4) }
		if offset < byte + width {
			if transcoded > 1 || (transcoded != 0 && (width != 4 || offset != byte))
				|| (offset != byte && index & 1 != 0) { return swift_foreign_count_failure() }
			start = units + i64(transcoded)
			if transcoded == 0 { aligned = (byte << 16) | (index & 12) | 1 }
			if offset == byte && index & 1 != 0 { aligned = index }
			break
		}
		units += if width == 4 { i64(2) } else { i64(1) }
		byte += width
	}
	if offset == count { start = units; aligned = index | 1 }
	// Finish counting before signed arithmetic; never add INT64_MIN/MAX first.
	for byte < count {
		lead := text[int(byte)]
		width := if lead < 0x80 { u64(1) } else if lead < 0xe0 { u64(2) } else if lead < 0xf0 { u64(3) } else { u64(4) }
		units += if width == 4 { i64(2) } else { i64(1) }; byte += width
	}
	if start < 0 || distance < -start || distance > units - start { return swift_foreign_count_failure() }
	if distance == 0 { return aligned | 4 }
	target := start + distance
	// Native's large-distance path returns the cached startIndex at zero.
	if target == 0 && distance <= -64 { return 15 }
	byte = 0; units = 0
	for byte < count {
		if units == target { return (byte << 16) | 5 }
		lead := text[int(byte)]
		width := if lead < 0x80 { u64(1) } else if lead < 0xe0 { u64(2) } else if lead < 0xf0 { u64(3) } else { u64(4) }
		if width == 4 && target == units + 1 { return (byte << 16) | 0x4004 }
		units += if width == 4 { i64(2) } else { i64(1) }; byte += width
	}
	return (count << 16) | 5
}

fn swift_utf16_offset(index u64, distance i64, first u64, second u64) u64 {
	return swift_utf16_offset_checked(index, distance, first, second) or { panic(err) }
}
