// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_binary32_integer_to_float_rounding_and_limits() {
	sign := u64(1) << 63; half_ulp := u64(1) << 39
	cases := [
		[u64(1), 0, 1, 0x3f800000], [u64(1), 1, 1, 0xbf800000],
		[u64(8), 1, 255, 0xbf800000], [u64(8), 1, 128, 0xc3000000],
		[u64(8), 0, 255, 0x437f0000], [u64(8), 0, 0x101, 0x3f800000],
		[u64(32), 1, 0x80000000, 0xcf000000], [u64(32), 0, 0xffffffff, 0x4f800000],
		[u64(64), 1, sign, 0xdf000000], [u64(64), 0, sign, 0x5f000000],
		[u64(64), 0, ~u64(0), 0x5f800000], [u64(64), 1, sign - 1, 0x5f000000],
		[u64(64), 1, ~u64(0), 0xbf800000], [u64(64), 0, 0, 0],
		[u64(32), 1, 0x1000001, 0x4b800000], [u64(32), 0, 0x1000003, 0x4b800002],
		[u64(32), 1, 0xfeffffff, 0xcb800000], [u64(32), 1, 0xfefffffd, 0xcb800002],
		[u64(24), 0, 0xffffff, 0x4b7fffff], [u64(25), 0, 0x1ffffff, 0x4c000000],
		[u64(64), 0, sign + half_ulp, 0x5f000000], [u64(64), 0, sign + 3 * half_ulp, 0x5f000002],
	]
	defer { unsafe { for row in cases { row.free() }; cases.free() } }
	for row in cases { assert binary32_from_integer(u32(row[0]), row[1] != 0, row[2])! == u32(row[3]) }
	println('AIR-BINARY32-FROM-INTEGER: ${cases.len} exact signed/unsigned, width-mask, RNE-tie and i64 limit patterns PASS')
}
fn test_binary32_float_to_integer_truncation_and_poison() {
	cases := [
		[u64(1), 1, 0x3f800000, 1, 0], [u64(1), 1, 0xbfc00000, 0, 1],
		[u64(1), 1, 0xc0000000, 1, 0], [u64(1), 0, 0x3ff33333, 0, 1],
		[u64(1), 0, 0x40000000, 1, 0], [u64(1), 0, 0xbf7fffff, 0, 0],
		[u64(1), 0, 0xbf800000, 1, 0], [u64(8), 1, 0xc3008000, 0, 128],
		[u64(8), 1, 0xc3010000, 1, 0], [u64(8), 1, 0x42ff8000, 0, 127],
		[u64(8), 1, 0x43000000, 1, 0], [u64(8), 0, 0x437f8000, 0, 255],
		[u64(8), 0, 0x43800000, 1, 0], [u64(24), 1, 0x4b000000, 1, 0],
		[u64(24), 1, 0xcb000000, 0, 0x800000], [u64(24), 1, 0xcb000001, 1, 0],
		[u64(25), 1, 0x4b800000, 1, 0], [u64(25), 1, 0xcb800000, 0, 0x1000000],
		[u64(25), 1, 0xcb800001, 1, 0], [u64(64), 1, 0xdf000000, 0, u64(1) << 63],
		[u64(64), 1, 0x5f000000, 1, 0], [u64(64), 1, 0x5effffff, 0, 0x7fffff8000000000],
		[u64(64), 0, 0x5f7fffff, 0, 0xffffff0000000000], [u64(64), 0, 0x5f800000, 1, 0],
		[u64(64), 1, 0xdf000001, 1, 0], [u64(64), 1, 0x7fc00000, 1, 0],
		[u64(64), 0, 0xff800001, 1, 0], [u64(8), 0, 0x7f800000, 1, 0],
		[u64(64), 1, 0xff800000, 1, 0], [u64(64), 0, 0x7f7fffff, 1, 0],
		[u64(8), 0, 0x80000001, 0, 0], [u64(8), 1, 0x3f7fffff, 0, 0],
		[u64(64), 1, 0x80000000, 0, 0], [u64(64), 0, 0, 0, 0],
	]
	defer { unsafe { for row in cases { row.free() }; cases.free() } }
	for row in cases {
		actual := binary32_to_integer(u32(row[0]), row[1] != 0, u32(row[2]))!
		assert actual.poison == (row[3] != 0)
		if !actual.poison { assert actual.value == row[4] }
	}
	for bits in [u32(0), 65]! {
		if _ := binary32_from_integer(bits, true, 1) { assert false, 'invalid source width' }
		if _ := binary32_to_integer(bits, true, 0) { assert false, 'invalid result width' }
	}
	println('AIR-BINARY32-TO-INTEGER: ${cases.len} exact fraction/zero/range/NaN/infinity patterns, explicit poison and width guards PASS')
}
fn test_binary32_exhaustive_small_integer_round_trips() {
	mut count := 0
	for bits in u32(1) .. 17 {
		for value in u64(0) .. u64(1) << bits {
			for signed in [false, true]! {
				floating := binary32_from_integer(bits, signed, value | (u64(1) << bits))!
				integer := binary32_to_integer(bits, signed, floating)!
				assert !integer.poison && integer.value == value
				count++
			}
		}
	}
	println('AIR-BINARY32-CAST-ROUNDTRIP: ${count} exhaustive signed/unsigned i1..i16 exact round trips PASS')
}
