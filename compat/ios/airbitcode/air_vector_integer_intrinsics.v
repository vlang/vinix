// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const vector_air_integer_cache_base = vector_air_clamp_cache_base + 16

fn air_vector_integer_name(name string) !(ScalarIntrinsic, int, u32) {
	id := if name.starts_with('air.mul_hi.s.v') { ScalarIntrinsic.smulh } else if name.starts_with('air.mul_hi.u.v') { ScalarIntrinsic.umulh } else if name.starts_with('air.add_sat.s.v') { ScalarIntrinsic.sadd_sat } else if name.starts_with('air.sub_sat.s.v') { ScalarIntrinsic.ssub_sat } else if name.starts_with('air.add_sat.u.v') { ScalarIntrinsic.uadd_sat } else if name.starts_with('air.sub_sat.u.v') { ScalarIntrinsic.usub_sat } else if name.starts_with('air.min.s.v') { ScalarIntrinsic.smin } else if name.starts_with('air.max.s.v') { ScalarIntrinsic.smax } else if name.starts_with('air.min.u.v') { ScalarIntrinsic.umin } else if name.starts_with('air.max.u.v') { ScalarIntrinsic.umax } else if name.starts_with('air.popcount.v') { ScalarIntrinsic.ctpop } else if name.starts_with('air.reverse_bits.v') { ScalarIntrinsic.bitreverse } else { return error('AIR vector integer: unsupported name') }
	count, bits := vector_integer_overload(name, if id == .ctpop { 14 } else if id == .bitreverse { 18 } else if scalar_integer_extremum(id) { 11 } else if scalar_integer_mulh(id) { 14 } else { 15 })!
	if bits != 32 { return error('AIR vector integer: i32 required') }
	return id, count, bits
}

fn air_vector_integer_key(id ScalarIntrinsic, count int, bits u32) !int {
	if count < 1 || count > 16 || bits != 32 { return error('AIR vector integer: cache shape') }
	operation := match id { .smulh { 0 } .umulh { 1 } .sadd_sat { 2 } .ssub_sat { 3 } .uadd_sat { 4 } .usub_sat { 5 } .smin { 6 } .smax { 7 } .umin { 8 } .umax { 9 } .ctpop { 10 } .bitreverse { 11 } else { return error('AIR vector integer: unsupported family') } }
	return vector_air_integer_cache_base + operation * 16 + count - 1
}

fn air_vector_intrinsic_key(id ScalarIntrinsic, count int, bits u32) !int {
	if id in [ScalarIntrinsic.ctpop, .bitreverse]! || scalar_integer_mulh(id) || scalar_integer_saturating(id) || scalar_integer_extremum(id) { return air_vector_integer_key(id, count, bits) }
	return air_vector_float_key(id, count, bits)
}
