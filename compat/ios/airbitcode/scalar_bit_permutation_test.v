// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

import math.bits

// Independent oracle: inspect every width position and obtain its packed rank
// from a standard-library population count of the lower mask positions.
fn bit_permutation_reference(extract bool, width u32, value u64, mask_value u64) u64 {
	x := value & constant_mask(width); mask := mask_value & constant_mask(width)
	mut result := u64(0)
	for position in u32(0) .. width {
		bit := u64(1) << position
		if mask & bit == 0 { continue }
		rank := bits.ones_count_64(mask & (bit - 1))
		if extract { if x & bit != 0 { result |= u64(1) << rank } }
		else { if (x >> rank) & 1 != 0 { result |= bit } }
	}
	return result
}
fn test_scalar_bit_permutations_widths_masks_and_round_trips() {
	mut comparisons := 0
	for width in u32(1) .. 65 {
		mask := constant_mask(width); sign := u64(1) << (width - 1)
		edges := [u64(0), mask, sign, sign - 1, sign + 1, u64(1), mask - 1, u64(0xaaaaaaaaaaaaaaaa), 0x5555555555555555, 0x0123456789abcdef, 0xfedcba9876543210, sign >> 1]!
		for op in ['pext', 'pdep'] {
			name := 'llvm.${op}.i${width}'; defer { unsafe { name.free() } }; id := scalar_intrinsic_name(name)!
			assert scalar_intrinsic_arity(id) == 2
			limit := if width <= 8 { int(u64(1) << (2 * width)) } else { 4096 }
			for sample in 0 .. 144 + limit {
				a := if sample < 144 { edges[sample / 12] } else if width <= 8 { u64(sample - 144) & mask } else { u64(sample) * u64(0x9e3779b97f4a7c15) }
				b := if sample < 144 { edges[sample % 12] } else if width <= 8 { u64(sample - 144) >> width } else { ~a ^ (a >> 17) }
				assert scalar_intrinsic_value(id, width, a, b)! == bit_permutation_reference(op == 'pext', width, a, b)
				extracted := scalar_intrinsic_value(.pext, width, a, b)!
				assert scalar_intrinsic_value(.pdep, width, extracted, b)! == a & b & mask
				deposited := scalar_intrinsic_value(.pdep, width, a, b)!
				count := bits.ones_count_64(b & mask)
				prefix := if count == 64 { ~u64(0) } else { (u64(1) << count) - 1 }
				assert scalar_intrinsic_value(.pext, width, deposited, b)! == a & prefix
				assert scalar_intrinsic_value(id, width, a, 0)! == 0
				assert scalar_intrinsic_value(id, width, a, mask)! == a & mask
				comparisons++
			}
			if _ := scalar_integer_intrinsic_value(id, width, 0) { assert false, 'unary bit-permutation evaluator' }
		}
	}
	for name in ['llvm.pext.i0', 'llvm.pdep.i01', 'llvm.pext.i65', 'llvm.pdep.i128', 'llvm.pext.i+1', 'llvm.pdep.i1x', 'llvm.pext.v2i32', 'llvm.pdep.f32', 'air.pext.i32'] {
		if _ := scalar_intrinsic_name(name) { assert false, 'invalid bit-permutation name' }
	}
	for width in [u32(0), 65, 128]! { if _ := scalar_integer_bit_permutation_value(.pext, width, 0, 0) { assert false, 'bit-permutation width' } }
	if _ := scalar_integer_bit_permutation_value(.ctpop, 32, 0, 0) { assert false, 'bit-permutation family' }
	assert comparisons == 651944
	println('AIR-SCALAR-BIT-PERMUTATION: ${comparisons} independent position/rank comparisons, exhaustive i1..i8 value-mask pairs, all i1..i64, 18432 boundary pairs, both round trips, empty/full masks and strict name/width/arity/evaluator guards PASS')
}
