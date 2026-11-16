// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const vector_air_extrema_cache_base = vector_air_fma_cache_base + 16

fn air_vector_extrema_name(name string) !(ScalarIntrinsic, int, u32) {
	id := if name.starts_with('air.fmin.v') { ScalarIntrinsic.air_fmin } else if name.starts_with('air.fmax.v') { ScalarIntrinsic.air_fmax } else { return error('AIR vector extrema: unsupported name') }
	count, bits := vector_float_overload(name, 10)!
	if bits != 32 { return error('AIR vector extrema: float32 required') }
	return id, count, bits
}

fn air_vector_extrema_key(id ScalarIntrinsic, count int, bits u32) !int {
	if id !in [.air_fmin, .air_fmax]! || count < 1 || count > 16 || bits != 32 { return error('AIR vector extrema: cache shape') }
	return vector_air_extrema_cache_base + int(id == .air_fmax) * 16 + count - 1
}

fn air_extrema_vector(id ScalarIntrinsic, left ScalarVectorValue, right ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
	air_vector_extrema_key(id, count, bits)!
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		a := left.lanes[lane]; b := right.lanes[lane]
		if (left.undef | right.undef) & (u16(1) << u32(lane)) != 0 { return error('AIR vector extrema: undef source lane') }
		if a.aggregate || a.vector || b.aggregate || b.vector { return error('AIR vector extrema: scalar lanes required') }
		result.lanes[lane] = if a.poison || b.poison { IntegerValue{poison: true} } else { IntegerValue{value: scalar_air_float_extremum(id, bits, a.value, b.value)!} }
	}
	return result
}
