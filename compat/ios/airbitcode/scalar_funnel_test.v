// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Independent oracle: choose each output bit from the conceptual two-word
// concatenation instead of composing two wide shifts as production does.
fn funnel_bit_reference(left bool, width u32, a u64, b u64, amount u64) u64 {
	shift := u32((amount & constant_mask(width)) % width); mut out := u64(0)
	for bit in u32(0) .. width {
		source := if left { bit + width - shift } else { bit + shift }
		value := if source >= width { (a >> (source - width)) & 1 } else { (b >> source) & 1 }
		out |= value << bit
	}
	return out
}
fn test_scalar_funnel_shifts_all_widths_and_rotations() {
	mut comparisons := 0
	for width in u32(1) .. 65 {
		mask := constant_mask(width)
		for op in ['fshl', 'fshr'] {
			name := 'llvm.${op}.i${width}'; defer { unsafe { name.free() } }; id := scalar_intrinsic_name(name)!
			assert scalar_intrinsic_arity(id) == 3
			for sample in 0 .. if width <= 5 { int(u64(1) << (3 * width)) } else { 4096 } {
				a := if width <= 5 { u64(sample) & mask } else { u64(sample) * u64(0x9e3779b97f4a7c15) }
				b := if width <= 5 { (u64(sample) >> width) & mask } else { ~a ^ (a >> 17) }
				amount := if width <= 5 { u64(sample) >> (2 * width) } else { a ^ (u64(sample) << 49) }
				assert scalar_integer_funnel_value(id, width, a, b, amount)! == funnel_bit_reference(op == 'fshl', width, a, b, amount)
				rotated := scalar_integer_funnel_value(.fshl, width, a, a, amount)!
				assert scalar_integer_funnel_value(.fshr, width, rotated, rotated, amount)! == a & mask
				comparisons++
			}
			assert scalar_integer_funnel_value(id, width, 0x12345678, 0xabcdef01, 0)! == (if op == 'fshl' { u64(0x12345678) } else { u64(0xabcdef01) }) & mask
			if _ := scalar_intrinsic_value(id, width, 0, 0) { assert false, 'binary funnel evaluator' }
			if _ := scalar_integer_intrinsic_value(id, width, 0) { assert false, 'unary funnel evaluator' }
		}
	}
	for name in ['llvm.fshl.i0', 'llvm.fshr.i01', 'llvm.fshl.i65', 'llvm.fshr.i128', 'llvm.fshl.i+1', 'llvm.fshr.i1x', 'llvm.fshl.v2i32', 'llvm.fshr.f32', 'air.fshl.i32'] {
		if _ := scalar_intrinsic_name(name) { assert false, 'invalid funnel name' }
	}
	for width in [u32(0), 65, 128]! { if _ := scalar_integer_funnel_value(.fshl, width, 0, 0, 0) { assert false, 'funnel width' } }
	if _ := scalar_integer_funnel_value(.ctpop, 32, 0, 0, 0) { assert false, 'funnel family' }
	println('AIR-SCALAR-FUNNEL: ${comparisons} independent bit-concatenation comparisons, all i1..i64, exhaustive i1..i5 triples, rotation round trips, zero-shift and name/width/arity/evaluator guards PASS')
}
