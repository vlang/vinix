// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn minmax_intrinsic_vector(id ScalarIntrinsic, left ScalarVectorValue, right ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
	if id !in [.minimum, .maximum]! { return error('AIR vector intrinsic: min/max family') }
	vector_float_intrinsic_key(id, count, bits)!
	mask := constant_mask(bits)
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		a := left.lanes[lane]; b := right.lanes[lane]
		if (left.undef | right.undef) & (u16(1) << u32(lane)) != 0 { return error('AIR vector intrinsic: undef source lane') }
		if a.aggregate || a.vector || b.aggregate || b.vector { return error('AIR vector intrinsic: scalar lanes required') }
		result.lanes[lane] = if a.poison || b.poison { IntegerValue{poison: true} } else { IntegerValue{value: scalar_intrinsic_value(id, bits, a.value & mask, b.value & mask)!} }
	}
	return result
}
