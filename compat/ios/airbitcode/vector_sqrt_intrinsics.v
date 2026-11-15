// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn sqrt_intrinsic_vector(source ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
	vector_float_intrinsic_key(.sqrt, count, bits)!
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		a := source.lanes[lane]
		if source.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector intrinsic: undef source lane') }
		if a.aggregate || a.vector { return error('AIR vector intrinsic: scalar lanes required') }
		result.lanes[lane] = if a.poison { IntegerValue{poison: true} } else { IntegerValue{value: scalar_intrinsic_value(.sqrt, bits, a.value & constant_mask(bits), 0)!} }
	}
	return result
}
