// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode
fn test_vector_ldexp_exact_values() {
 mut checks := 0
 for bits in [u32(16), 32]! {
		sign := u64(1) << (bits - 1); one := if bits == 16 { u64(0x3c00) } else { u64(0x3f800000) }
		two := if bits == 16 { u64(0x4000) } else { u64(0x40000000) }; half := if bits == 16 { u64(0x3800) } else { u64(0x3f000000) }
		inf := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }; nan := if bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) }
		minimum_normal := if bits == 16 { u64(0x0400) } else { u64(0x00800000) }; fraction_bits := if bits == 16 { 10 } else { 23 }
		cases := [[one, u64(0), one], [one, u64(1), two], [one, u64(0xffffffff), half],
			[one | sign, u64(1), two | sign], [u64(1), u64(fraction_bits), minimum_normal],
			[minimum_normal, u64(u32(-fraction_bits)), 1], [u64(1), u64(0xffffffff), 0],
			[u64(3), u64(0xffffffff), 2], [sign | 1, u64(0xffffffff), sign], [sign | 3, u64(0xffffffff), sign | 2],
			[inf - 1, u64(1), inf], [(inf - 1) | sign, u64(1), inf | sign],
			[one, u64(0x7fffffff), inf], [one | sign, u64(0x7fffffff), inf | sign],
			[one, u64(0x80000000), 0], [one | sign, u64(0x80000000), sign],
			[u64(0), u64(0x7fffffff), 0], [sign, u64(0x80000000), sign],
			[inf, u64(0x80000000), inf], [inf | sign, u64(0x7fffffff), inf | sign],
			[inf + 1, u64(0), nan], [(nan + 1) | sign, u64(0xffffffff), nan],
			[one, u64(0x100000001), two], [one, u64(0x1ffffffff), half]]
		defer { unsafe { for row in cases { row.free() }; cases.free() } }

 for count in 1 .. 17 { for row in cases {
  mut input := ScalarVectorValue{}; mut exponents := ScalarVectorValue{}
  for lane in 0 .. count { input.lanes[lane] = IntegerValue{value: row[0] | ~constant_mask(bits)}; exponents.lanes[lane] = IntegerValue{value: row[1] | ~u64(0xffffffff)} }
  a := input; b := exponents; result := ldexp_intrinsic_vector(input, exponents, bits, count)!
  for lane in 0 .. count { assert result.lanes[lane] == IntegerValue{value: row[2]}; checks++ }; assert input == a && exponents == b && result.undef == 0
 } }
 }
 assert checks == 6528
 println("AIR-VECTOR-LDEXP-VALUES: ${checks} exact scaling/subnormal/tie/zero/infinity/NaN/INT_MIN/MAX/masking lane results across both formats and all counts, snapshots PASS")
}
