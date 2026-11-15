// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_vector_fma_exact_values_and_single_rounding() {
 mut checks := 0
 for bits in [u32(16), 32]! {
		sign := u64(1) << (bits - 1)
		one := if bits == 16 { u64(0x3c00) } else { u64(0x3f800000) }
		two := if bits == 16 { u64(0x4000) } else { u64(0x40000000) }
		half := if bits == 16 { u64(0x3800) } else { u64(0x3f000000) }
		inf := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }
		nan := if bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) }
		epsilon_squared := if bits == 16 { u64(0x10) } else { u64(0x28800000) }
		one_and_half := one + ((two - one) >> 1)
		cases := [[one, one, one, two], [one, one, one | sign, u64(0)],
			[one | sign, one, one | sign, two | sign], [u64(0), one, 0, 0],
			[sign, one, sign, sign], [sign, one, 0, 0], [u64(0), one | sign, sign, sign],
			[one, sign, one, one], [inf, one, one | sign, inf], [inf | sign, one, one, inf | sign],
			[inf, one, inf | sign, nan], [inf, 0, one, nan], [u64(0), inf, one, nan],
			[one, one, inf, inf], [one, one, inf | sign, inf | sign],
			[inf + 1, one, one, nan], [one, (inf + 1) | sign, one, nan], [one, one, inf + 1, nan],
			[inf - 1, two, (inf - 1) | sign, inf - 1], [u64(1), half, 1, 2],
			[u64(1), 1, 0, 0], [sign | 1, 1, 0, sign],
			[one + 1, one - 2, one | sign, epsilon_squared | sign],
			[one - 2, one + 1, one | sign, epsilon_squared | sign],
			[(one + 1) | sign, one - 2, one, epsilon_squared],
			[one, one, 1, one], [one, one, sign | 1, one],
			[one_and_half, one + 1, sign | 1, one_and_half + 1],
			[one_and_half, one + 1, 1, one_and_half + 2]]
		defer { unsafe { for row in cases { row.free() }; cases.free() } }

 for count in 1 .. 17 { for row in cases { mut a := ScalarVectorValue{}; mut b := ScalarVectorValue{}; mut c := ScalarVectorValue{}; for lane in 0 .. count { a.lanes[lane] = IntegerValue{value: row[0] | ~constant_mask(bits)}; b.lanes[lane] = IntegerValue{value: row[1] | ~constant_mask(bits)}; c.lanes[lane] = IntegerValue{value: row[2] | ~constant_mask(bits)} }; before_a := a; before_b := b; before_c := c; result := fma_intrinsic_vector(a, b, c, bits, count)!; for lane in 0 .. count { assert result.lanes[lane] == IntegerValue{value: row[3]}, "exact fused pattern"; checks++ }; assert a == before_a && b == before_b && c == before_c && result.undef == 0 } }
 }
 assert checks == 7888
 println("AIR-VECTOR-FMA-VALUES: ${checks} exact lane results across all counts, both formats, masking, snapshots, cancellation, overflow rescue, underflow, zeros and NaNs PASS")
}
