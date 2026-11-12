// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Independent polynomial convolution: compute each output coefficient's parity
// from all input-bit pairs on its diagonal. No shifted-term accumulation.
fn clmul_reference(width u32, a u64, b u64) u64 {
	x := a & constant_mask(width); y := b & constant_mask(width)
	mut result := u64(0)
	for output in u32(0) .. width {
		mut parity := u64(0)
		for left in u32(0) .. output + 1 { parity ^= ((x >> left) & 1) & ((y >> (output - left)) & 1) }
		result |= parity << output
	}
	return result
}
fn test_scalar_clmul_widths_polynomial_identities_and_truncation() {
	mut comparisons := 0
	for width in u32(1) .. 65 {
		mask := constant_mask(width); sign := u64(1) << (width - 1)
		edges := [u64(0), mask, sign, sign - 1, sign + 1, u64(1), mask - 1, u64(0xaaaaaaaaaaaaaaaa), 0x5555555555555555, 0x0123456789abcdef, 0xfedcba9876543210, sign >> 1]!
		name := 'llvm.clmul.i${width}'; defer { unsafe { name.free() } }; id := scalar_intrinsic_name(name)!
		assert id == .clmul && scalar_intrinsic_arity(id) == 2
		limit := if width <= 8 { int(u64(1) << (2 * width)) } else { 4096 }
		for sample in 0 .. 144 + limit {
			a := if sample < 144 { edges[sample / 12] } else if width <= 8 { u64(sample - 144) & mask } else { u64(sample) * u64(0x9e3779b97f4a7c15) }
			b := if sample < 144 { edges[sample % 12] } else if width <= 8 { u64(sample - 144) >> width } else { ~a ^ (a >> 17) }
			actual := scalar_intrinsic_value(id, width, a, b)!
			assert actual == clmul_reference(width, a, b)
			assert scalar_integer_clmul(width, b, a)! == actual
			assert scalar_integer_clmul(width, a, 0)! == 0
			assert scalar_integer_clmul(width, a, 1)! == a & mask
			c := (a ^ (a >> 23)) & mask
			assert scalar_integer_clmul(width, a, b ^ c)! == actual ^ scalar_integer_clmul(width, a, c)!
			mut square := u64(0)
			for position in u32(0) .. (width + 1) / 2 { if a & (u64(1) << position) != 0 { square |= u64(1) << (position * 2) } }
			assert scalar_integer_clmul(width, a, a)! == square
			comparisons++
		}
		assert scalar_integer_clmul(width, sign, 2)! == 0
		if _ := scalar_integer_intrinsic_value(id, width, 0) { assert false, 'unary carry-less multiply evaluator' }
	}
	for name in ['llvm.clmul.i0', 'llvm.clmul.i01', 'llvm.clmul.i65', 'llvm.clmul.i128', 'llvm.clmul.i+1', 'llvm.clmul.i1x', 'llvm.clmul.v2i32', 'llvm.clmul.f32', 'air.clmul.i32'] {
		if _ := scalar_intrinsic_name(name) { assert false, 'invalid carry-less multiply name' }
	}
	for width in [u32(0), 65, 128]! { if _ := scalar_integer_clmul(width, 0, 0) { assert false, 'carry-less multiply width' } }
	assert comparisons == 325972
	println('AIR-SCALAR-CLMUL: ${comparisons} independent polynomial-convolution comparisons, exhaustive i1..i8 pairs, all i1..i64, 9216 boundary pairs, commutativity/distributivity/square/zero/identity/truncation and strict name/width/arity/evaluator guards PASS')
}
