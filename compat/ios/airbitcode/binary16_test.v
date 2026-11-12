// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_binary16_arithmetic_rounding_and_special_values() {
	cases := [
		[u16(0), 0x3c00, 0x3c00, 0x4000], [u16(0), 0x3c00, 0x1000, 0x3c00],
		[u16(0), 0x3c00, 0x1600, 0x3c02], [u16(0), 0xbc00, 0x9000, 0xbc00],
		[u16(0), 0x7bff, 0x7bff, 0x7c00], [u16(0), 1, 1, 2],
		[u16(0), 0x03ff, 1, 0x0400], [u16(1), 0x0400, 0x03ff, 1],
		[u16(1), 0x3c00, 0x3c00, 0], [u16(0), 0, 0x8000, 0],
		[u16(0), 0x8000, 0x8000, 0x8000], [u16(0), 0x7c00, 0x7c00, 0x7c00],
		[u16(1), 0x7c00, 0x7c00, 0x7e00], [u16(2), 0x3c00, 0x4000, 0x4000],
		[u16(2), 0x0400, 0x3800, 0x0200], [u16(2), 1, 0x3800, 0],
		[u16(2), 3, 0x3800, 2], [u16(2), 0x7bff, 0x4000, 0x7c00],
		[u16(2), 0x8000, 0xc000, 0], [u16(2), 0x8001, 0x3800, 0x8000],
		[u16(2), 0x7c00, 0, 0x7e00], [u16(4), 0x3c00, 0x4200, 0x3555],
		[u16(4), 0x4000, 0x4200, 0x3955], [u16(4), 1, 0x4000, 0],
		[u16(4), 3, 0x4000, 2], [u16(4), 0x0400, 0x4000, 0x0200],
		[u16(4), 0x7c00, 0x7c00, 0x7e00], [u16(4), 0x3c00, 0, 0x7c00],
		[u16(4), 0xbc00, 0, 0xfc00], [u16(4), 0, 0, 0x7e00],
		[u16(4), 0x8000, 0x4000, 0x8000], [u16(4), 0x7bff, 1, 0x7c00],
		[u16(6), 0x4700, 0x4400, 0x4200], [u16(6), 0xc700, 0xc400, 0xc200],
		[u16(6), 0xc400, 0x4000, 0x8000], [u16(6), 0x0400, 0x03ff, 1],
		[u16(6), 0x3c00, 3, 1], [u16(6), 0x7bff, 11, 6],
		[u16(6), 0x7c00, 0x3c00, 0x7e00], [u16(6), 0x3c00, 0, 0x7e00],
		[u16(6), 0x8001, 0xfc00, 0x8001],
	]
	defer { unsafe { for row in cases { row.free() }; cases.free() } }
	for row in cases { assert binary16_binary(row[0], row[1], row[2])! == row[3], '${row}' }
	for op in [u32(0), 1, 2, 4, 6]! { assert binary16_binary(op, 0x7c01, 0x3c00)! == binary16_nan }
	if _ := binary16_binary(3, 0, 0) { assert false, 'unknown half opcode' }
	println('AIR-BINARY16-ARITHMETIC: ${cases.len} exact rounding/underflow/overflow/sign/zero/infinity/remainder patterns, preferred NaNs and opcode guard PASS')
}
fn test_binary16_comparisons_and_integer_oracle_remainders() {
	less := [false, false, false, false, true, true, true, true, false, false, false, false, true, true, true, true]!
	equal := [false, true, false, true, false, true, false, true, false, true, false, true, false, true, false, true]!
	for op in u32(0) .. 16 {
		assert binary16_compare(op, 0x3c00, 0x4000)! == less[op]
		assert binary16_compare(op, 0, 0x8000)! == equal[op]
		assert binary16_compare(op, 0x7c01, 0)! == (op >= 8)
	}
	assert binary16_compare(4, 0xfc00, 0xfbff)!
	if _ := binary16_compare(16, 0, 0) { assert false, 'unknown half predicate' }
	for dividend in u16(0) .. 1024 {
		for divisor in u16(1) .. 33 {
			for signs in u16(0) .. 4 {
				sign := (signs & 1) << 15
				assert binary16_binary(6, dividend | sign, divisor | ((signs >> 1) << 15))! == (dividend % divisor) | sign
			}
		}
	}
	println('AIR-BINARY16-COMPARE-REMAINDER: all sixteen predicates, signed zero, signaling NaN, negative infinity, guard and 131,072 integer-oracle subnormal remainders PASS')
}
