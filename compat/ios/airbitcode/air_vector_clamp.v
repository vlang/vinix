// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const vector_air_clamp_cache_base = vector_air_extrema_cache_base + 32

fn air_vector_clamp_name(name string) !(ScalarIntrinsic, int, u32) {
	if !name.starts_with('air.clamp.v') { return error('AIR vector clamp: unsupported name') }
	count, bits := vector_float_overload(name, 11)!
	if bits != 32 { return error('AIR vector clamp: float32 required') }
	return ScalarIntrinsic.air_clamp, count, bits
}

fn air_vector_clamp_key(id ScalarIntrinsic, count int, bits u32) !int {
	if id != .air_clamp || count < 1 || count > 16 || bits != 32 { return error('AIR vector clamp: cache shape') }
	return vector_air_clamp_cache_base + count - 1
}

fn air_clamp_vector(x ScalarVectorValue, low ScalarVectorValue, high ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
	air_vector_clamp_key(.air_clamp, count, bits)!
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		a := x.lanes[lane]; b := low.lanes[lane]; c := high.lanes[lane]
		if (x.undef | low.undef | high.undef) & (u16(1) << u32(lane)) != 0 { return error('AIR vector clamp: undef source lane') }
		if a.aggregate || a.vector || b.aggregate || b.vector || c.aggregate || c.vector { return error('AIR vector clamp: scalar lanes required') }
		result.lanes[lane] = if a.poison || b.poison || c.poison { IntegerValue{poison: true} } else { scalar_air_float_clamp(bits, a.value, b.value, c.value)! }
	}
	return result
}
