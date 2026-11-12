// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_binary16_integer_conversion_patterns_and_guards() {
	from := [
		[u64(1), 0, 1, 0x3c00], [u64(1), 1, 1, 0xbc00],
		[u64(8), 0, 0x1ff, 0x5bf8], [u64(8), 1, 0x1ff, 0xbc00],
		[u64(64), 0, 0, 0], [u64(64), 0, 1, 0x3c00],
		[u64(64), 0, 2048, 0x6800], [u64(64), 0, 2049, 0x6800],
		[u64(64), 0, 2051, 0x6802], [u64(64), 1, u64(0) - 2049, 0xe800],
		[u64(64), 1, u64(0) - 2051, 0xe802],
		[u64(16), 0, 65504, 0x7bff], [u64(64), 0, 65519, 0x7bff],
		[u64(64), 0, 65520, 0x7c00], [u64(64), 1, u64(0) - 65520, 0xfc00],
		[u64(64), 0, ~u64(0), 0x7c00], [u64(64), 1, u64(1) << 63, 0xfc00],
		[u64(64), 1, (u64(1) << 63) - 1, 0x7c00],
	]
	to := [
		[u64(8), 0, 0, 0, 0], [u64(8), 1, 0x8000, 0, 0],
		[u64(8), 0, 1, 0, 0], [u64(8), 0, 0x8001, 0, 0],
		[u64(8), 0, 0xbbff, 0, 0], [u64(8), 0, 0xbc00, 0, 1],
		[u64(8), 1, 0xd804, 128, 0], [u64(8), 1, 0xd808, 0, 1],
		[u64(8), 0, 0x5bfc, 255, 0], [u64(8), 0, 0x5c00, 0, 1],
		[u64(8), 1, 0x57f8, 127, 0], [u64(8), 1, 0x5800, 0, 1],
		[u64(1), 1, 0xbc00, 1, 0], [u64(1), 1, 0xbe00, 1, 0],
		[u64(1), 1, 0xc000, 0, 1], [u64(1), 1, 0x3800, 0, 0],
		[u64(1), 1, 0x3c00, 0, 1], [u64(1), 0, 0x3e00, 1, 0],
		[u64(1), 0, 0x4000, 0, 1], [u64(16), 0, 0x7bff, 65504, 0],
		[u64(16), 1, 0x7bff, 0, 1], [u64(17), 1, 0x7bff, 65504, 0],
		[u64(64), 1, 0xfbff, u64(0) - 65504, 0],
		[u64(64), 0, 0x7c00, 0, 1], [u64(64), 1, 0xfc00, 0, 1],
		[u64(64), 0, 0x7c01, 0, 1], [u64(64), 1, 0xfe55, 0, 1],
	]
	defer { unsafe { for row in from { row.free() }; from.free(); for row in to { row.free() }; to.free() } }
	for row in from { assert binary16_from_integer(u32(row[0]), row[1] != 0, row[2])! == u16(row[3]), '${row}' }
	for row in to { result := binary16_to_integer(u32(row[0]), row[1] != 0, u16(row[2]))!; assert result.poison == (row[4] != 0) && (result.poison || result.value == row[3]), '${row}' }
	for width in [u32(0), 65]! {
		if _ := binary16_from_integer(width, false, 0) { assert false, 'invalid integer width' }
		if _ := binary16_to_integer(width, true, 0) { assert false, 'invalid integer width' }
	}
	println('AIR-BINARY16-INTEGER-PATTERNS: ${from.len} exact integer-to-half and ${to.len} half-to-integer patterns, direct rounding/overflow, fractional bounds, poison and width guards PASS')
}
fn test_binary16_integer_exact_narrow_round_trips() {
	mut count := 0
	for bits in u32(1) .. 12 {
		for word in u64(0) .. u64(1) << bits {
			for signed in [false, true]! {
				half := binary16_from_integer(bits, signed, word)!
				back := binary16_to_integer(bits, signed, half)!
				assert !back.poison && back.value == word
				count++
			}
		}
	}
	println('AIR-BINARY16-INTEGER-ROUNDTRIP: ${count} exhaustive signed/unsigned i1..i11 exact round trips PASS')
}
