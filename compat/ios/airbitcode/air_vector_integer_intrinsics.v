// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const vector_air_integer_cache_base = vector_air_clamp_cache_base + 16

fn air_vector_integer_name(name string) !(ScalarIntrinsic, int, u32) {
	id := if name.starts_with('air.mul_hi.s.v') { ScalarIntrinsic.smulh } else if name.starts_with('air.mul_hi.u.v') { ScalarIntrinsic.umulh } else if name.starts_with('air.add_sat.s.v') { ScalarIntrinsic.sadd_sat } else if name.starts_with('air.sub_sat.s.v') { ScalarIntrinsic.ssub_sat } else if name.starts_with('air.add_sat.u.v') { ScalarIntrinsic.uadd_sat } else if name.starts_with('air.sub_sat.u.v') { ScalarIntrinsic.usub_sat } else if name.starts_with('air.min.s.v') { ScalarIntrinsic.smin } else if name.starts_with('air.max.s.v') { ScalarIntrinsic.smax } else if name.starts_with('air.min.u.v') { ScalarIntrinsic.umin } else if name.starts_with('air.max.u.v') { ScalarIntrinsic.umax } else if name.starts_with('air.popcount.v') { ScalarIntrinsic.ctpop } else if name.starts_with('air.reverse_bits.v') { ScalarIntrinsic.bitreverse } else if name.starts_with('air.clz.v') { ScalarIntrinsic.ctlz } else if name.starts_with('air.ctz.v') { ScalarIntrinsic.cttz } else { return error('AIR vector integer: unsupported name') }
	count, bits := vector_integer_overload(name, if scalar_integer_zero_count(id) { 9 } else if id == .ctpop { 14 } else if id == .bitreverse { 18 } else if scalar_integer_extremum(id) { 11 } else if scalar_integer_mulh(id) { 14 } else { 15 })!
	if bits != 32 && !(bits == 64 && (id in [ScalarIntrinsic.ctpop, .bitreverse]! || scalar_integer_extremum(id))) { return error('AIR vector integer: unsupported width/family') }
	return id, count, bits
}

fn air_vector_integer_key(id ScalarIntrinsic, count int, bits u32) !int {
	if count < 1 || count > 16 { return error('AIR vector integer: cache shape') }
	if bits == 64 && id in [ScalarIntrinsic.ctpop, .bitreverse]! { return vector_air_integer_cache_base + 224 + int(id == .bitreverse) * 16 + count - 1 }
	if bits == 64 && scalar_integer_extremum(id) { return vector_air_integer_cache_base + 256 + vector_integer_extremum_index(id)! * 16 + count - 1 }
	if bits != 32 { return error('AIR vector integer: cache width/family') }
	operation := match id { .smulh { 0 } .umulh { 1 } .sadd_sat { 2 } .ssub_sat { 3 } .uadd_sat { 4 } .usub_sat { 5 } .smin { 6 } .smax { 7 } .umin { 8 } .umax { 9 } .ctpop { 10 } .bitreverse { 11 } .ctlz { 12 } .cttz { 13 } else { return error('AIR vector integer: unsupported family') } }
	return vector_air_integer_cache_base + operation * 16 + count - 1
}

fn air_vector_intrinsic_key(id ScalarIntrinsic, count int, bits u32) !int {
	if scalar_integer_zero_count(id) || id in [ScalarIntrinsic.ctpop, .bitreverse]! || scalar_integer_mulh(id) || scalar_integer_saturating(id) || scalar_integer_extremum(id) { return air_vector_integer_key(id, count, bits) }
	return air_vector_float_key(id, count, bits)
}
