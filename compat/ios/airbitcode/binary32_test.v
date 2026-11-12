// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_binary32_rounding_gradual_underflow_and_special_values() {
	cases := [
		[u32(0), 0x3f800000, 0x3f800000, 0x40000000],
		[u32(0), 0x3f800000, 0x33800000, 0x3f800000], // Halfway, even.
		[u32(0), 0x3f800000, 0x34400000, 0x3f800002], // Halfway, odd.
		[u32(0), 0xbf800000, 0xb3800000, 0xbf800000],
		[u32(0), 0x7f7fffff, 0x7f7fffff, 0x7f800000],
		[u32(0), 1, 1, 2], [u32(0), 0x007fffff, 1, 0x00800000],
		[u32(1), 0x00800000, 0x007fffff, 1], [u32(1), 0x3f800000, 0x3f800000, 0],
		[u32(0), 0, 0x80000000, 0], [u32(0), 0x80000000, 0x80000000, 0x80000000],
		[u32(0), 0x7f800000, 0x7f800000, 0x7f800000],
		[u32(1), 0x7f800000, 0x7f800000, 0x7fc00000],
		[u32(2), 0x3f800000, 0x40000000, 0x40000000],
		[u32(2), 0x00800000, 0x3f000000, 0x00400000],
		[u32(2), 1, 0x3f000000, 0], [u32(2), 3, 0x3f000000, 2],
		[u32(2), 0x7f7fffff, 0x40000000, 0x7f800000],
		[u32(2), 0x80000000, 0xc0000000, 0],
		[u32(2), 0x80000001, 0x3f000000, 0x80000000],
		[u32(2), 0x00800000, 0x3f7fffff, 0x00800000],
		[u32(2), 0x7f800000, 0, 0x7fc00000],
		[u32(4), 0x3f800000, 0x40400000, 0x3eaaaaab],
		[u32(4), 0x40000000, 0x40400000, 0x3f2aaaab],
		[u32(4), 1, 0x40000000, 0], [u32(4), 3, 0x40000000, 2],
		[u32(4), 0x00800000, 0x40000000, 0x00400000],
		[u32(4), 0x7f800000, 0x7f800000, 0x7fc00000],
		[u32(4), 0x3f800000, 0, 0x7f800000], [u32(4), 0xbf800000, 0, 0xff800000],
		[u32(4), 0, 0, 0x7fc00000], [u32(4), 0x80000000, 0x40000000, 0x80000000],
		[u32(4), 0x7f7fffff, 1, 0x7f800000], [u32(4), 1, 0x7f800000, 0],
	]
	defer { unsafe { for row in cases { row.free() }; cases.free() } }
	for row in cases { assert binary32_binary(row[0], row[1], row[2])! == row[3], '${row}' }
	for op in [u32(0), 1, 2, 4, 6]! { assert binary32_binary(op, 0x7f800001, 0x3f800000)! == binary32_nan }
	if _ := binary32_binary(3, 0, 0) { assert false, 'unsupported float opcode' }
	println('AIR-BINARY32-ARITHMETIC: ${cases.len} exact RNE/underflow/overflow/zero/infinity patterns, NaNs and unsupported opcode PASS')
}
fn test_binary32_remainder_exact_sign_subnormal_and_extreme_quotients() {
	cases := [
		[u32(0x40e00000), 0x40800000, 0x40400000], // 7 % 4 = 3, not IEEE remainder -1.
		[u32(0xc0e00000), 0x40800000, 0xc0400000],
		[u32(0x40e00000), 0xc0800000, 0x40400000],
		[u32(0xc0e00000), 0xc0800000, 0xc0400000],
		[u32(0x40b00000), 0x40000000, 0x3fc00000], // 5.5 % 2 = 1.5.
		[u32(0x3f800000), 0x40000000, 0x3f800000],
		[u32(0xbf800000), 0x40000000, 0xbf800000],
		[u32(0x40800000), 0xc0000000, 0],
		[u32(0xc0800000), 0x40000000, 0x80000000],
		[u32(0xbf800000), 0x3f800000, 0x80000000],
		[u32(0), 0xbf800000, 0], [u32(0x80000000), 0x3f800000, 0x80000000],
		[u32(0x3f800000), 0x7f800000, 0x3f800000],
		[u32(0x80000001), 0xff800000, 0x80000001],
		[u32(0x00800000), 0x007fffff, 1],
		[u32(0x00800001), 0x00800000, 1],
		[u32(0x007fffff), 3, 1], [u32(0x807fffff), 3, 0x80000001],
		[u32(0x3f800000), 3, 2], [u32(0x3f800000), 11, 6],
		[u32(0x7f7fffff), 1, 0], [u32(0xff7fffff), 1, 0x80000000],
		[u32(0x7f7fffff), 11, 10], [u32(0x7f7ffffe), 11, 2],
		[u32(0x7f800000), 0x3f800000, 0x7fc00000],
		[u32(0xff800000), 0x7f800000, 0x7fc00000],
		[u32(0x3f800000), 0, 0x7fc00000], [u32(0), 0x80000000, 0x7fc00000],
		[u32(0x7f800001), 0x3f800000, 0x7fc00000],
		[u32(0x3f800000), 0xffc12345, 0x7fc00000],
	]
	defer { unsafe { for row in cases { row.free() }; cases.free() } }
	for row in cases { assert binary32_binary(6, row[0], row[1])! == row[2], '${row}' }
	mut comparisons := 0
	// Subnormal encodings are integer multiples of 2^-149: an independent
	// integer modulo oracle checks exact bits and both signs of both operands.
	for dividend in u32(0) .. 1024 {
		for divisor in u32(1) .. 33 {
			for signs in u32(0) .. 4 {
				sign := (signs & 1) << 31
				assert binary32_binary(6, dividend | sign, divisor | ((signs >> 1) << 31))! == (dividend % divisor) | sign
				comparisons++
			}
		}
	}
	println('AIR-BINARY32-REMAINDER: ${cases.len} exact sign/zero/subnormal/extreme/NaN patterns and ${comparisons} integer-oracle subnormal comparisons PASS')
}
fn test_binary32_ordered_unordered_predicates() {
	less := [false, false, false, false, true, true, true, true, false, false, false, false, true, true, true, true]!
	equal := [false, true, false, true, false, true, false, true, false, true, false, true, false, true, false, true]!
	for op in u32(0) .. 16 {
		assert binary32_compare(op, 0x3f800000, 0x40000000)! == less[op]
		assert binary32_compare(op, 0, 0x80000000)! == equal[op]
		assert binary32_compare(op, 0x7f800001, 0)! == (op >= 8)
	}
	assert binary32_compare(4, 0xff800000, 0xff7fffff)!
	assert binary32_compare(4, 0xbf800000, 0x80000000)!
	assert binary32_compare(2, 0x7f800000, 0x7f7fffff)!
	if _ := binary32_compare(16, 0, 0) { assert false, 'unknown predicate' }
	println('AIR-BINARY32-COMPARE: all 16 predicates, signed zero, negative values/infinity and signaling NaN classification PASS')
}
