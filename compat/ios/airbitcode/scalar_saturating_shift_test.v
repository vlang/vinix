// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Independent oracle: repeat checked doubling rather than comparing magnitude
// against a shifted limit. Every signed operation remains within i64 bounds.
fn saturating_shift_reference(signed bool, width u32, value u64, amount u64) IntegerValue {
	mask := constant_mask(width); x := value & mask; shift := amount & mask
	if shift >= u64(width) { return IntegerValue{poison: true} }
	if !signed {
		mut v := x
		for _ in u64(0) .. shift { if v > mask - v { return IntegerValue{value: mask} }; v += v }
		return IntegerValue{value: v}
	}
	sign := u64(1) << (width - 1); maximum := i64(sign - 1); minimum := -maximum - 1
	mut v := if x & sign == 0 { i64(x) } else { -i64((~x) & mask) - 1 }
	for _ in u64(0) .. shift {
		if v > maximum / 2 { return IntegerValue{value: u64(maximum)} }
		if v < minimum / 2 { return IntegerValue{value: u64(minimum) & mask} }
		v += v
	}
	return IntegerValue{value: u64(v) & mask}
}
fn test_scalar_saturating_shifts_widths_amounts_and_poison() {
	mut comparisons := 0; mut poison_cases := 0
	for width in u32(1) .. 65 {
		mask := constant_mask(width); sign := u64(1) << (width - 1)
		edges := [u64(0), mask, sign, sign - 1, sign + 1, u64(1), mask - 1, u64(0xaaaaaaaaaaaaaaaa), 0x5555555555555555, 0x0123456789abcdef, 0xfedcba9876543210, sign >> 1]!
		shifts := [u64(0), 1, u64(width - 1), u64(width), u64(width + 1), mask, 2, u64(width / 2), 31, 32, 63, 64]!
		for op in ['sshl.sat', 'ushl.sat'] {
			name := 'llvm.${op}.i${width}'; defer { unsafe { name.free() } }; id := scalar_intrinsic_name(name)!
			assert scalar_intrinsic_arity(id) == 2
			limit := if width <= 8 { int(u64(1) << (2 * width)) } else { 4096 }
			for sample in 0 .. 144 + limit {
				a := if sample < 144 { edges[sample / 12] } else if width <= 8 { u64(sample - 144) & mask } else { u64(sample) * u64(0x9e3779b97f4a7c15) }
				b := if sample < 144 { shifts[sample % 12] } else if width <= 8 { u64(sample - 144) >> width } else { u64(sample) % u64(width + 2) }
				expected := saturating_shift_reference(op.starts_with('s'), width, a, b)
				actual := scalar_integer_saturating_shift_value(id, width, a, b)!
				assert actual.poison == expected.poison
				if actual.poison { poison_cases++ } else { assert actual.value == expected.value }
				assert scalar_integer_saturating_shift_value(id, width, a, 0)!.value == a & mask
				comparisons++
			}
			assert scalar_integer_saturating_shift_value(id, width, 0, width)!.poison
			if _ := scalar_intrinsic_value(id, width, 0, 0) { assert false, 'untagged saturating-shift evaluator' }
			if _ := scalar_integer_intrinsic_value(id, width, 0) { assert false, 'unary saturating-shift evaluator' }
		}
	}
	for name in ['llvm.sshl.sat.i0', 'llvm.ushl.sat.i01', 'llvm.sshl.sat.i65', 'llvm.ushl.sat.i128', 'llvm.sshl.sat.i+1', 'llvm.ushl.sat.i1x', 'llvm.sshl.sat.v2i32', 'llvm.ushl.sat.f32', 'air.sshl.sat.i32'] {
		if _ := scalar_intrinsic_name(name) { assert false, 'invalid saturating shift name' }
	}
	for width in [u32(0), 65, 128]! { if _ := scalar_integer_saturating_shift_value(.sshl_sat, width, 0, 0) { assert false, 'saturating shift width' } }
	if _ := scalar_integer_saturating_shift_value(.ctpop, 32, 0, 0) { assert false, 'saturating shift family' }
	assert comparisons == 651944
	println('AIR-SCALAR-SATURATING-SHIFT: ${comparisons} independent checked-doubling comparisons (${poison_cases} poison), exhaustive i1..i8 pairs, all i1..i64, 18432 value/amount edge pairs, zero identity/zero overshift and strict name/width/arity/tagged-evaluator guards PASS')
}
