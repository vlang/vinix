// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_scalar_ldexp_scaling_and_limits() {
	mut count := 0
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
		for row in cases { assert scalar_intrinsic_value(.ldexp, bits, row[0], row[1])! == row[2], '${bits}: ${row}'; count++ }
		name := 'llvm.ldexp.f${bits}.i32'; defer { unsafe { name.free() } }; assert scalar_intrinsic_arity(scalar_intrinsic_name(name)!) == 2
	}
	for name in ['llvm.ldexp.f16', 'llvm.ldexp.f32.i64', 'llvm.ldexp.f64.i32', 'llvm.ldexp.v2f32.v2i32', 'air.ldexp.f32.i32'] { if _ := scalar_intrinsic_name(name) { assert false, 'unsupported scaling name' } }
	println('AIR-SCALAR-LDEXP: ${count} exact scaling/subnormal/tie/zero/infinity/NaN/INT_MIN/MAX/masking cases and name/arity guards PASS')
}
