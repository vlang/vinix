// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const vector_air_fma_cache_base = vector_air_unary_cache_base + 112

fn air_vector_float_name(name string) !(ScalarIntrinsic, int, u32) {
	if name.starts_with('air.clamp.v') { return air_vector_clamp_name(name) }
	if name.starts_with('air.fmin.v') || name.starts_with('air.fmax.v') { return air_vector_extrema_name(name) }
	if !name.starts_with('air.fma.v') { return air_vector_unary_name(name) }
	count, bits := vector_float_overload(name, 9)!
	if bits != 32 { return error('AIR vector FMA: float32 required') }
	return ScalarIntrinsic.fma, count, bits
}

fn air_vector_float_key(id ScalarIntrinsic, count int, bits u32) !int {
	if id == .air_clamp { return air_vector_clamp_key(id, count, bits)! }
	if id in [.air_fmin, .air_fmax]! { return air_vector_extrema_key(id, count, bits)! }
	if id != .fma { return air_vector_unary_key(id, count, bits) }
	if count < 1 || count > 16 || bits != 32 { return error('AIR vector FMA: cache shape') }
	return vector_air_fma_cache_base + count - 1
}
