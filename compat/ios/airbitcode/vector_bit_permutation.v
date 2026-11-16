// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn bit_permutation_vector(id ScalarIntrinsic, left ScalarVectorValue, right ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
	if !scalar_integer_bit_permutation(id) { return error('AIR vector intrinsic: bit permutation family') }
	vector_float_intrinsic_key(id, count, bits)!
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		if (left.undef | right.undef) & (u16(1) << u32(lane)) != 0 { return error('AIR vector intrinsic: undef source lane') }
		a := left.lanes[lane]; b := right.lanes[lane]
		if a.aggregate || a.vector || b.aggregate || b.vector { return error('AIR vector intrinsic: scalar lanes required') }
		result.lanes[lane] = if a.poison || b.poison { IntegerValue{poison: true} } else { IntegerValue{value: scalar_integer_bit_permutation_value(id, bits, a.value, b.value)!} }
	}
	return result
}
