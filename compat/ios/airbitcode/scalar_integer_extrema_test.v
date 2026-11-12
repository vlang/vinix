// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Independent signed oracle: negative magnitude construction stays within i64
// even for INT64_MIN; production instead compares sign-bit-flipped u64 keys.
fn extrema_signed_reference(value u64, width u32) i64 {
	x := value & constant_mask(width)
	return if x & (u64(1) << (width - 1)) == 0 { i64(x) } else { -i64((~x) & constant_mask(width)) - 1 }
}
fn test_scalar_integer_extrema_widths_signedness_and_symmetry() {
	mut comparisons := 0
	for width in u32(1) .. 65 {
		mask := constant_mask(width)
		for op in ['smin', 'smax', 'umin', 'umax'] {
			name := 'llvm.${op}.i${width}'; defer { unsafe { name.free() } }; id := scalar_intrinsic_name(name)!
			assert scalar_intrinsic_arity(id) == 2
			for sample in 0 .. if width <= 8 { int(u64(1) << (2 * width)) } else { 4096 } {
				a := if width <= 8 { u64(sample) & mask } else { u64(sample) * u64(0x9e3779b97f4a7c15) }
				b := if width <= 8 { u64(sample) >> width } else { ~a ^ (a >> 17) }
				x := a & mask; y := b & mask
				less := if op.starts_with('s') { extrema_signed_reference(x, width) < extrema_signed_reference(y, width) } else { x < y }
				expected := if less == op.ends_with('min') { x } else { y }
				assert scalar_intrinsic_value(id, width, a, b)! == expected
				assert scalar_intrinsic_value(id, width, b, a)! == expected
				assert scalar_intrinsic_value(id, width, a, a)! == x
				comparisons++
			}
			if _ := scalar_integer_intrinsic_value(id, width, 0) { assert false, 'unary extremum evaluator' }
		}
	}
	for name in ['llvm.smin.i0', 'llvm.smax.i01', 'llvm.umin.i65', 'llvm.umax.i128', 'llvm.smin.i+1', 'llvm.smax.i1x', 'llvm.umin.v2i32', 'llvm.umax.f32', 'air.smin.i32'] {
		if _ := scalar_intrinsic_name(name) { assert false, 'invalid integer extremum name' }
	}
	for width in [u32(0), 65, 128]! { if _ := scalar_integer_extremum_value(.smin, width, 0, 0) { assert false, 'extremum width' } }
	if _ := scalar_integer_extremum_value(.ctpop, 32, 0, 0) { assert false, 'extremum family' }
	for width in [u32(1), 64]! {
		sign := u64(1) << (width - 1); mask := constant_mask(width)
		assert scalar_intrinsic_value(.smin, width, sign, sign - 1)! == sign
		assert scalar_intrinsic_value(.smax, width, sign, sign - 1)! == sign - 1
		assert scalar_intrinsic_value(.umin, width, mask, 0)! == 0
		assert scalar_intrinsic_value(.umax, width, mask, 0)! == mask
	}
	println('AIR-SCALAR-INTEGER-EXTREMA: ${comparisons} independent value comparisons, exhaustive i1..i8 pairs, all i1..i64, symmetry/idempotence, signed limits and strict name/width/arity/evaluator guards PASS')
}
