// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn saturating_signed(value u64, width u32) i64 {
	x := value & constant_mask(width)
	return if x & (u64(1) << (width - 1)) == 0 { i64(x) } else { -i64((~x) & constant_mask(width)) - 1 }
}
// Independent oracle: signed arithmetic uses checked margins before computing
// any result. Unsigned addition uses two 32-bit limbs and an explicit carry.
fn saturating_reference(id ScalarIntrinsic, width u32, a u64, b u64) u64 {
	mask := constant_mask(width); x := a & mask; y := b & mask
	if id == .uadd_sat {
		low := (x & 0xffffffff) + (y & 0xffffffff)
		high := (x >> 32) + (y >> 32) + (low >> 32)
		result := ((high & 0xffffffff) << 32) | (low & 0xffffffff)
		return if high >> 32 != 0 || result & ~mask != 0 { mask } else { result }
	}
	if id == .usub_sat { return if x >= y { x - y } else { u64(0) } }
	left := saturating_signed(x, width); right := saturating_signed(y, width)
	maximum := i64((u64(1) << (width - 1)) - 1); minimum := -maximum - 1
	if id == .sadd_sat {
		if right > 0 && left > maximum - right { return u64(maximum) }
		if right < 0 && left < minimum - right { return u64(minimum) & mask }
		return u64(left + right) & mask
	}
	if right < 0 && left > maximum + right { return u64(maximum) }
	if right > 0 && left < minimum + right { return u64(minimum) & mask }
	return u64(left - right) & mask
}
fn test_scalar_saturating_widths_boundaries_and_identities() {
	mut comparisons := 0
	for width in u32(1) .. 65 {
		mask := constant_mask(width); sign := u64(1) << (width - 1)
		edges := [u64(0), mask, sign, sign - 1, sign + 1, u64(1), mask - 1, u64(0xaaaaaaaaaaaaaaaa), 0x5555555555555555, 0x0123456789abcdef, 0xfedcba9876543210, sign >> 1]!
		for op in ['sadd.sat', 'uadd.sat', 'ssub.sat', 'usub.sat'] {
			name := 'llvm.${op}.i${width}'; defer { unsafe { name.free() } }; id := scalar_intrinsic_name(name)!
			assert scalar_intrinsic_arity(id) == 2
			limit := if width <= 8 { int(u64(1) << (2 * width)) } else { 4096 }
			for sample in 0 .. 144 + limit {
				a := if sample < 144 { edges[sample / 12] } else if width <= 8 { u64(sample - 144) & mask } else { u64(sample) * u64(0x9e3779b97f4a7c15) }
				b := if sample < 144 { edges[sample % 12] } else if width <= 8 { u64(sample - 144) >> width } else { ~a ^ (a >> 17) }
				expected := saturating_reference(id, width, a, b)
				assert scalar_intrinsic_value(id, width, a, b)! == expected
				if id in [.sadd_sat, .uadd_sat]! { assert scalar_intrinsic_value(id, width, b, a)! == expected }
				assert scalar_intrinsic_value(id, width, a, 0)! == a & mask
				comparisons++
			}
			if _ := scalar_integer_intrinsic_value(id, width, 0) { assert false, 'unary saturating evaluator' }
		}
	}
	for name in ['llvm.sadd.sat.i0', 'llvm.uadd.sat.i01', 'llvm.ssub.sat.i65', 'llvm.usub.sat.i128', 'llvm.sadd.sat.i+1', 'llvm.uadd.sat.i1x', 'llvm.ssub.sat.v2i32', 'llvm.usub.sat.f32', 'air.sadd.sat.i32'] {
		if _ := scalar_intrinsic_name(name) { assert false, 'invalid saturating name' }
	}
	for width in [u32(0), 65, 128]! { if _ := scalar_integer_saturating_value(.sadd_sat, width, 0, 0) { assert false, 'saturating width' } }
	if _ := scalar_integer_saturating_value(.ctpop, 32, 0, 0) { assert false, 'saturating family' }
	assert comparisons == 1303888
	println('AIR-SCALAR-SATURATING: ${comparisons} independent margin/carry comparisons, exhaustive i1..i8 pairs, all i1..i64, 36864 edge pairs, commutative addition/zero identities and strict name/width/arity/evaluator guards PASS')
}
