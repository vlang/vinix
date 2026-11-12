// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

import math.bits

fn test_scalar_zero_counts_all_widths_flags_and_poison() {
	mut comparisons := 0; mut poison_cases := 0
	for width in u32(1) .. 65 {
		for op in ['ctlz', 'cttz'] {
			name := 'llvm.${op}.i${width}'; defer { unsafe { name.free() } }; id := scalar_intrinsic_name(name)!
			assert scalar_intrinsic_arity(id) == 2
			for sample in 0 .. if width <= 16 { int(u64(1) << width) } else { 4096 } {
				value := if width <= 16 { u64(sample) } else { (u64(sample) * u64(0x9e3779b97f4a7c15)) ^ (u64(sample) << 47) }
				x := value & constant_mask(width)
				expected := if x == 0 { u64(width) } else if op == 'ctlz' { u64(bits.leading_zeros_64(x) - int(64 - width)) } else { u64(bits.trailing_zeros_64(x)) }
				for flag in [u64(0), 1]! {
					actual := scalar_integer_zero_count_value(id, width, value, flag)!
					assert actual.poison == (x == 0 && flag == 1)
					if actual.poison { poison_cases++ } else { assert actual.value == expected }
					comparisons++
				}
			}
			assert scalar_integer_zero_count_value(id, width, 0, 0)!.value == width
			assert scalar_integer_zero_count_value(id, width, 0, 1)!.poison
			if _ := scalar_intrinsic_value(id, width, 0, 0) { assert false, 'untagged zero-count evaluator' }
			if _ := scalar_integer_intrinsic_value(id, width, 0) { assert false, 'unary zero-count evaluator' }
		}
	}
	for name in ['llvm.ctlz.i0', 'llvm.cttz.i01', 'llvm.ctlz.i65', 'llvm.cttz.i128', 'llvm.ctlz.i+1', 'llvm.cttz.i1x', 'llvm.ctlz.v2i32', 'llvm.cttz.f32', 'air.ctlz.i32'] {
		if _ := scalar_intrinsic_name(name) { assert false, 'invalid zero count name' }
	}
	for width in [u32(0), 65, 128]! {
		if _ := scalar_integer_zero_count_value(.ctlz, width, 0, 0) { assert false, 'zero count width' }
	}
	if _ := scalar_integer_zero_count_value(.ctpop, 32, 0, 0) { assert false, 'zero count family' }
	if _ := scalar_integer_zero_count_value(.cttz, 32, 0, 2) { assert false, 'nonboolean zero count flag' }
	println('AIR-SCALAR-ZERO-COUNTS: ${comparisons} standard-library comparisons (${poison_cases} poison), all i1..i64/flags, explicit zero boundaries and name/width/arity/tagged-evaluator guards PASS')
}
