// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Scan selected positions and packed positions independently of the production
// helper's low-set-bit walk.
fn vector_permutation_reference(id ScalarIntrinsic, bits u32, input u64, selection u64) u64 {
	mut rank := u32(0); mut result := u64(0)
	for position in u32(0) .. bits {
		if (selection >> position) & 1 == 0 { continue }
		from := if id == .pext { position } else { rank }
		to := if id == .pext { rank } else { position }
		result |= ((input >> from) & 1) << to
		rank++
	}
	return result
}
fn test_vector_bit_permutation_values() {
	mut checks := 0
	for id in [ScalarIntrinsic.pext, .pdep]! { for bits in u32(1) .. 65 {
		for count in 1 .. 17 { for sample in 0 .. 8 {
			mut a := ScalarVectorValue{}; mut b := a
			for lane in 0 .. count {
				a.lanes[lane] = IntegerValue{value: (u64(sample + lane) * u64(0x9e3779b97f4a7c15)) | ~constant_mask(bits)}
				b.lanes[lane] = IntegerValue{value: [u64(0), ~u64(0), 1, u64(1) << (bits - 1), 0xaaaaaaaaaaaaaaaa, 0x5555555555555555, 0x9e3779b97f4a7c15, 0x0123456789abcdef]![(sample + lane) % 8] | ~constant_mask(bits)}
			}
			before_a := a; before_b := b; result := bit_permutation_vector(id, a, b, bits, count)!
			for lane in 0 .. count { assert result.lanes[lane] == IntegerValue{value: vector_permutation_reference(id, bits, a.lanes[lane].value, b.lanes[lane].value)}; checks++ }
			assert a == before_a && b == before_b && result.undef == 0
		} }
		if bits <= 8 {
			pairs := int(u64(1) << (bits * 2))
			for offset in 0 .. (pairs + 15) / 16 {
				mut a := ScalarVectorValue{}; mut b := a
				for lane in 0 .. 16 { k := u64((offset * 16 + lane) % pairs); a.lanes[lane] = IntegerValue{value: k & constant_mask(bits)}; b.lanes[lane] = IntegerValue{value: k >> bits} }
				result := bit_permutation_vector(id, a, b, bits, 16)!
				for lane in 0 .. 16 { assert result.lanes[lane].value == vector_permutation_reference(id, bits, a.lanes[lane].value, b.lanes[lane].value); checks++ }
			}
		}
	} }
	println('AIR-VECTOR-BIT-PERMUTATION-VALUES: ${checks} independent values, exhaustive i1..i8 pairs, all widths/counts, upper bits, zero/full/sparse masks and snapshots PASS')
}
fn test_vector_bit_permutation_states_and_guards() {
	mut checks := 0
	for id in [ScalarIntrinsic.pext, .pdep]! { for bits in u32(1) .. 65 { for count in 1 .. 17 {
		for side in 0 .. 2 { for target in 0 .. count {
			mut a := ScalarVectorValue{}; mut b := a
			if side == 0 { a.lanes[target] = IntegerValue{poison: true} } else { b.lanes[target] = IntegerValue{poison: true} }
			result := bit_permutation_vector(id, a, b, bits, count)!
			for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); checks++ }
			assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
			if side == 0 { a.undef = u16(1) << u32(target) } else { b.undef = u16(1) << u32(target) }
			if _ := bit_permutation_vector(id, a, b, bits, count) { assert false, 'undef dominates even a zero mask' }; checks++
		} }
	} } }
	for name in ['llvm.pext.i32', 'llvm.pext.v0i1', 'llvm.pext.v01i8', 'llvm.pdep.v17i32', 'llvm.pext.v2i0', 'llvm.pext.v2i065', 'llvm.pdep.v2i65', 'llvm.pdep.v2f32', 'llvm.pext.v2i32.extra', 'llvm.pext.nxv2i32', 'llvm.pext.v99999999999999i32'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false, name } }
	for id in [ScalarIntrinsic.clmul, .ctpop]! { if _ := bit_permutation_vector(id, ScalarVectorValue{}, ScalarVectorValue{}, 32, 1) { assert false } }
	for bits in [u32(0), 65]! { if _ := bit_permutation_vector(.pext, ScalarVectorValue{}, ScalarVectorValue{}, bits, 1) { assert false } }
	for count in [0, 17] { if _ := bit_permutation_vector(.pdep, ScalarVectorValue{}, ScalarVectorValue{}, 32, count) { assert false } }
	for side in 0 .. 2 { for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut a := ScalarVectorValue{}; mut b := a; if side == 0 { a.lanes[0] = tag } else { b.lanes[0] = tag }; if _ := bit_permutation_vector(.pext, a, b, 32, 1) { assert false } } }
	println('AIR-VECTOR-BIT-PERMUTATION-STATES: ${checks} poison/undef/freeze states, names, types and family guards PASS')
}
