// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_scalar_integer_abs_widths_flags_and_minimum() {
	mut comparisons := 0; mut poison_cases := 0
	for width in u32(1) .. 65 {
		mask := constant_mask(width); sign := u64(1) << (width - 1)
		name := 'llvm.abs.i${width}'; defer { unsafe { name.free() } }
		assert scalar_intrinsic_name(name)! == .iabs
		assert scalar_intrinsic_arity(.iabs) == 2
		for sample in 0 .. if width <= 16 { int(u64(1) << width) } else { 4096 } {
			value := if width <= 16 { u64(sample) } else { (u64(sample) * u64(0x9e3779b97f4a7c15)) ^ (u64(sample) << 47) }; x := value & mask
			// Reconstruct a signed value safely; handle each width's minimum
			// explicitly before signed negation, so INT64_MIN is never negated.
			mut expected := sign
			if x != sign {
				signed := if x & sign == 0 { i64(x) } else { -i64((~x) & mask) - 1 }
				expected = u64(if signed < 0 { -signed } else { signed })
			}
			for flag in [u64(0), 1]! {
				actual := scalar_integer_abs_value(width, value, flag)!
				assert actual.poison == (x == sign && flag == 1)
				if actual.poison { poison_cases++ } else {
					assert actual.value == expected
					assert scalar_integer_abs_value(width, actual.value, flag)!.value == expected
				}
				comparisons++
			}
		}
		assert scalar_integer_abs_value(width, sign, 0)!.value == sign
		assert scalar_integer_abs_value(width, sign, 1)!.poison
		assert scalar_integer_abs_value(width, 0, 1)!.value == 0
		if _ := scalar_intrinsic_value(.iabs, width, 0, 0) { assert false, 'untagged abs evaluator' }
		if _ := scalar_integer_intrinsic_value(.iabs, width, 0) { assert false, 'unary abs evaluator' }
	}
	for name in ['llvm.abs.i0', 'llvm.abs.i01', 'llvm.abs.i65', 'llvm.abs.i128', 'llvm.abs.i+1', 'llvm.abs.i1x', 'llvm.abs.v2i32', 'llvm.abs.f32', 'air.abs.i32'] {
		if _ := scalar_intrinsic_name(name) { assert false, 'invalid integer abs name' }
	}
	for width in [u32(0), 65, 128]! { if _ := scalar_integer_abs_value(width, 0, 0) { assert false, 'integer abs width' } }
	if _ := scalar_integer_abs_value(32, 0, 2) { assert false, 'nonboolean integer abs flag' }
	println('AIR-SCALAR-INTEGER-ABS: ${comparisons} independent signed-magnitude comparisons (${poison_cases} poison), all i1..i64/flags, narrow exhaustive values, idempotence/minimum boundaries and strict name/width/arity/tagged-evaluator guards PASS')
}
