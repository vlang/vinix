// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_binary16_precision_conversion_exact_patterns() {
	widen := [
		[u32(0), 0], [u32(0x8000), 0x80000000],
		[u32(1), 0x33800000], [u32(0x8001), 0xb3800000],
		[u32(0x03ff), 0x387fc000], [u32(0x0400), 0x38800000],
		[u32(0x3c00), 0x3f800000], [u32(0xbc00), 0xbf800000],
		[u32(0x7bff), 0x477fe000], [u32(0xfbff), 0xc77fe000],
		[u32(0x7c00), 0x7f800000], [u32(0xfc00), 0xff800000],
		[u32(0x7c01), 0x7fc00000], [u32(0xfe55), 0x7fc00000],
	]
	narrow := [
		[u32(0), 0], [u32(0x80000000), 0x8000],
		[u32(1), 0], [u32(0x80000001), 0x8000],
		[u32(0x33000000), 0], [u32(0x32ffffff), 0],
		[u32(0x33000001), 1], [u32(0xb3000000), 0x8000],
		[u32(0x33800000), 1], [u32(0x33bfffff), 1],
		[u32(0x33c00000), 2], [u32(0xb3c00000), 0x8002],
		[u32(0x387fc000), 0x03ff], [u32(0x387fe000), 0x0400],
		[u32(0x387fdfff), 0x03ff], [u32(0x38800000), 0x0400],
		[u32(0x3f800000), 0x3c00], [u32(0x3f801000), 0x3c00],
		[u32(0x3f800fff), 0x3c00], [u32(0x3f801001), 0x3c01],
		[u32(0x3f803000), 0x3c02], [u32(0xbf803000), 0xbc02],
		[u32(0x477fe000), 0x7bff], [u32(0x477fefff), 0x7bff],
		[u32(0x477ff000), 0x7c00], [u32(0xc77ff000), 0xfc00],
		[u32(0x7f7fffff), 0x7c00], [u32(0xff7fffff), 0xfc00],
		[u32(0x7f800000), 0x7c00], [u32(0xff800000), 0xfc00],
		[u32(0x7f800001), 0x7e00], [u32(0xffc12345), 0x7e00],
	]
	defer { unsafe { for row in widen { row.free() }; widen.free(); for row in narrow { row.free() }; narrow.free() } }
	for row in widen { assert binary16_to_binary32(u16(row[0])) == row[1], '${row}' }
	for row in narrow { assert binary16_from_binary32(row[0]) == u16(row[1]), '${row}' }
	println('AIR-BINARY16-PATTERNS: ${widen.len} exact widening and ${narrow.len} exact narrowing patterns, ties, signed zero, subnormals, overflow and preferred NaNs PASS')
}
fn test_binary16_exhaustive_precision_round_trip() {
	for raw in u32(0) .. 65536 {
		wide := binary16_to_binary32(u16(raw))
		expected := if raw & 0x7fff > 0x7c00 { u16(0x7e00) } else { u16(raw) }
		assert binary16_from_binary32(wide) == expected
	}
	println('AIR-BINARY16-ROUNDTRIP: all 65,536 half encodings, exact finite/infinite/zero round trips and preferred conversion NaNs PASS')
}
