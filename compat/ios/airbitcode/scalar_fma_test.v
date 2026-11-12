// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_scalar_fma_exact_values_and_single_rounding() {
	mut count := 0
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
		for row in cases { assert scalar_fma(bits, row[0], row[1], row[2])! == row[3], '${bits}: ${row}'; count++ }
		for row in [cases[18], cases[19], cases[22]]! {
			product := if bits == 16 { u64(binary16_binary(2, u16(row[0]), u16(row[1]))!) } else { u64(binary32_binary(2, u32(row[0]), u32(row[1]))!) }
			separate := if bits == 16 { u64(binary16_binary(0, u16(product), u16(row[2]))!) } else { u64(binary32_binary(0, u32(product), u32(row[2]))!) }
			assert separate != row[3], 'unfused arithmetic must differ'
		}
		name := 'llvm.fma.f${bits}'; defer { unsafe { name.free() } }
		assert scalar_intrinsic_arity(scalar_intrinsic_name(name)!) == 3
		optional_name := 'llvm.fmuladd.f${bits}'; defer { unsafe { optional_name.free() } }
		assert scalar_intrinsic_arity(scalar_intrinsic_name(optional_name)!) == 3
	}
	if _ := scalar_fma(64, 0, 0, 0) { assert false, 'unsupported FMA precision' }
	if _ := scalar_intrinsic_value(.fma, 32, 0, 0) { assert false, 'binary evaluator accepted ternary operation' }
	if _ := scalar_intrinsic_value(.fmuladd, 32, 0, 0) { assert false, 'binary evaluator accepted optional ternary operation' }
	for name in ['llvm.fma.f64', 'llvm.fma.v2f32', 'llvm.fmuladd.f64', 'llvm.fmuladd.v2f32', 'air.fma.f32'] { if _ := scalar_intrinsic_name(name) { assert false, 'unsupported FMA name' } }
	println('AIR-SCALAR-FMA: ${count} exact cancellation/overflow/underflow/zero/infinity/NaN results, six distinguishing unfused controls and arity/name/precision guards PASS')
}
