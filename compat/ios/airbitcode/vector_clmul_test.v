// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Compute each coefficient independently, without the production term walk.
fn vector_clmul_reference(bits u32, a u64, b u64) u64 {
	mut result := u64(0)
	for power in u32(0) .. bits {
		mut coefficient := u64(0)
		for left in u32(0) .. power + 1 { coefficient ^= ((a >> left) & 1) & ((b >> (power - left)) & 1) }
		result |= coefficient << power
	}
	return result
}
fn test_vector_clmul_values_and_identities() {
	mut checks := 0; mut identities := 0
	for bits in u32(1) .. 65 {
		for count in 1 .. 17 { for sample in 0 .. 8 {
			mut a := ScalarVectorValue{}; mut b := a; mut c := a; mut combined := a
			for lane in 0 .. count {
				a.lanes[lane] = IntegerValue{value: (u64(sample + lane) * u64(0x9e3779b97f4a7c15)) | ~constant_mask(bits)}
				b.lanes[lane] = IntegerValue{value: [u64(0), 1, ~u64(0), u64(1) << (bits - 1), 2, 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15, 0x0123456789abcdef]![(sample + lane) % 8] | ~constant_mask(bits)}
				c.lanes[lane] = IntegerValue{value: u64(sample + lane + 11) * u64(0xd1b54a32d192ed03)}
				combined.lanes[lane] = IntegerValue{value: b.lanes[lane].value ^ c.lanes[lane].value}
			}
			before_a := a; before_b := b; result := clmul_vector(a, b, bits, count)!
			swapped := clmul_vector(b, a, bits, count)!; other := clmul_vector(a, c, bits, count)!; distributed := clmul_vector(a, combined, bits, count)!
			for lane in 0 .. count {
				assert result.lanes[lane] == IntegerValue{value: vector_clmul_reference(bits, a.lanes[lane].value, b.lanes[lane].value)}; checks++
				assert swapped.lanes[lane] == result.lanes[lane] && distributed.lanes[lane].value == result.lanes[lane].value ^ other.lanes[lane].value; identities += 2
			}
			assert a == before_a && b == before_b && result.undef == 0
		} }
		if bits <= 8 {
			pairs := int(u64(1) << (bits * 2))
			for offset in 0 .. (pairs + 15) / 16 {
				mut a := ScalarVectorValue{}; mut b := a
				for lane in 0 .. 16 { k := u64((offset * 16 + lane) % pairs); a.lanes[lane] = IntegerValue{value: k & constant_mask(bits)}; b.lanes[lane] = IntegerValue{value: k >> bits} }
				result := clmul_vector(a, b, bits, 16)!
				for lane in 0 .. 16 { assert result.lanes[lane].value == vector_clmul_reference(bits, a.lanes[lane].value, b.lanes[lane].value); checks++ }
			}
		}
	}
	println('AIR-VECTOR-CLMUL-VALUES: ${checks} independent polynomial coefficients, exhaustive i1..i8 pairs, all widths/counts, upper bits and snapshots; ${identities} commutativity/distributivity identities PASS')
}
fn test_vector_clmul_states_and_guards() {
	mut checks := 0
	for bits in u32(1) .. 65 { for count in 1 .. 17 { for side in 0 .. 2 { for target in 0 .. count {
		mut a := ScalarVectorValue{}; mut b := a
		if side == 0 { a.lanes[target] = IntegerValue{poison: true} } else { b.lanes[target] = IntegerValue{poison: true} }
		result := clmul_vector(a, b, bits, count)!
		for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); checks++ }
		assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
		if side == 0 { a.undef = u16(1) << u32(target) } else { b.undef = u16(1) << u32(target) }
		if _ := clmul_vector(a, b, bits, count) { assert false, 'undef dominates a zero multiplier' }; checks++
	} } } }
	for name in ['llvm.clmul.i32', 'llvm.clmul.v0i1', 'llvm.clmul.v01i8', 'llvm.clmul.v17i32', 'llvm.clmul.v2i0', 'llvm.clmul.v2i065', 'llvm.clmul.v2i65', 'llvm.clmul.v2f32', 'llvm.clmul.v2i32.extra', 'llvm.clmul.nxv2i32', 'llvm.clmul.v99999999999999i32'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false, name } }
	for bits in [u32(0), 65]! { if _ := clmul_vector(ScalarVectorValue{}, ScalarVectorValue{}, bits, 1) { assert false } }
	for count in [0, 17] { if _ := clmul_vector(ScalarVectorValue{}, ScalarVectorValue{}, 32, count) { assert false } }
	for side in 0 .. 2 { for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut a := ScalarVectorValue{}; mut b := a; if side == 0 { a.lanes[0] = tag } else { b.lanes[0] = tag }; if _ := clmul_vector(a, b, 32, 1) { assert false } } }
	println('AIR-VECTOR-CLMUL-STATES: ${checks} poison/undef/freeze states, names, widths/counts and scalar-tag guards PASS')
}
