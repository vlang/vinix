// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const vector_air_integer_cache_base = vector_air_clamp_cache_base + 16

fn air_vector_integer_name(name string) !(ScalarIntrinsic, int, u32) {
	id := if name.starts_with('air.mul_hi.s.v') { ScalarIntrinsic.smulh } else if name.starts_with('air.mul_hi.u.v') { ScalarIntrinsic.umulh } else { return error('AIR vector integer: unsupported name') }
	count, bits := vector_integer_overload(name, 14)!
	if bits != 32 { return error('AIR vector integer: i32 required') }
	return id, count, bits
}

fn air_vector_integer_key(id ScalarIntrinsic, count int, bits u32) !int {
	if !scalar_integer_mulh(id) || count < 1 || count > 16 || bits != 32 { return error('AIR vector integer: cache shape') }
	return vector_air_integer_cache_base + int(id == .umulh) * 16 + count - 1
}

fn air_vector_intrinsic_key(id ScalarIntrinsic, count int, bits u32) !int {
	if scalar_integer_mulh(id) { return air_vector_integer_key(id, count, bits) }
	return air_vector_float_key(id, count, bits)
}
