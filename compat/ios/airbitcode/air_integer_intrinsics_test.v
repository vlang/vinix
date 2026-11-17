// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_air_integer_intrinsic_identity() {
	assert scalar_air_integer_cache_base == 2154 && scalar_intrinsic_cache_slots == 2204
	for i, name in ['air.popcount.i32', 'air.reverse_bits.i32'] {
		id, slot := air_integer_intrinsic(name)!
		assert slot == i && id == if i == 0 { ScalarIntrinsic.ctpop } else { ScalarIntrinsic.bitreverse }
		assert scalar_intrinsic_name(name)! == id && scalar_intrinsic_arity(id) == 1
		assert scalar_integer_intrinsic_width(name, id)! == 32
		if _ := scalar_integer_intrinsic_width(name, if i == 0 { ScalarIntrinsic.bitreverse } else { ScalarIntrinsic.ctpop }) { assert false }
	}
	for name in ['air.popcount.i1', 'air.popcount.i16', 'air.popcount.i032', 'air.popcount.i+32', 'air.popcount.v2i32', 'air.popcount.f32', 'air.popcount.i32.spoof', 'air.reverse_bits.i0', 'air.reverse_bits.i16', 'air.reverse_bits.v4i32', 'air.reverse_bits.i32.spoof', 'air.ctpop.i32', 'air.bitreverse.i32', 'air.ctlz.i32'] {
		if _ := scalar_intrinsic_name(name) { assert false, name }
	}
	println('AIR-INTEGER-NAMES: two exact i32 names, separate appended slots, unary identity and unsupported width/vector/family/spelling guards PASS')
}

fn test_air_integer_multiply_high_identity() {
	for i, name in ['air.mul_hi.s.i32', 'air.mul_hi.u.i32'] {
		id, slot := air_integer_intrinsic(name)!
		assert slot == 12 + i && id == if i == 0 { ScalarIntrinsic.smulh } else { ScalarIntrinsic.umulh }
		assert scalar_intrinsic_name(name)! == id && scalar_intrinsic_arity(id) == 2 && scalar_integer_mulh(id)
		assert scalar_integer_intrinsic_width(name, id)! == 32
		if _ := scalar_integer_intrinsic_width(name, .ctpop) { assert false }
	}
	for name in ['air.mul_hi.i32', 'air.mul_hi.s.i16', 'air.mul_hi.s.i032', 'air.mul_hi.u.i+32', 'air.mul_hi.s.v2i32', 'air.mul_hi.u.f32', 'air.mul_hi.u.i32.spoof', 'air.smulh.i32', 'air.umulh.i32', 'air.mul_hi.x.i32'] {
		if _ := scalar_intrinsic_name(name) { assert false, name }
	}
	println('AIR-MULTIPLY-HIGH-NAMES: two exact signed/unsigned i32 names, appended slots, binary identity and width/vector/family/spelling guards PASS')
}

fn test_air_integer_saturating_identity() {
	ids := [ScalarIntrinsic.sadd_sat, .ssub_sat, .uadd_sat, .usub_sat]!
	for i, name in ['air.add_sat.s.i32', 'air.sub_sat.s.i32', 'air.add_sat.u.i32', 'air.sub_sat.u.i32'] {
		id, slot := air_integer_intrinsic(name)!
		assert id == ids[i] && slot == 8 + i && scalar_integer_saturating(id)
		assert scalar_intrinsic_name(name)! == id && scalar_intrinsic_arity(id) == 2
		assert scalar_integer_intrinsic_width(name, id)! == 32
		if _ := scalar_integer_intrinsic_width(name, ids[(i + 1) % 4]) { assert false }
	}
	for name in ['air.add_sat.i32', 'air.sub_sat.i32', 'air.add_sat.s.i16', 'air.add_sat.s.i032', 'air.add_sat.s.i+32', 'air.add_sat.s.v2i32', 'air.sub_sat.u.f32', 'air.sub_sat.u.i32.spoof', 'air.sadd.sat.i32', 'air.usub.sat.i32', 'air.add_sat.x.i32'] {
		if _ := scalar_intrinsic_name(name) { assert false, name }
	}
	println('AIR-SATURATING-NAMES: four exact signed/unsigned i32 names, appended slots, binary identity and width/vector/family/spelling guards PASS')
}

fn test_air_integer_zero_count_identity() {
	for i, name in ['air.clz.i32', 'air.ctz.i32'] {
		id, slot := air_integer_intrinsic(name)!
		assert slot == 6 + i && id == if i == 0 { ScalarIntrinsic.ctlz } else { ScalarIntrinsic.cttz }
		assert scalar_intrinsic_name(name)! == id && scalar_intrinsic_arity(id) == 2 && scalar_integer_poison_flag(id)
		assert scalar_integer_intrinsic_width(name, id)! == 32
		assert scalar_integer_zero_count_value(id, 32, 0, 0)!.value == 32
		if _ := scalar_integer_intrinsic_width(name, .ctpop) { assert false }
	}
	for name in ['air.clz.i16', 'air.ctz.i1', 'air.clz.i032', 'air.clz.i+32', 'air.ctz.i32.spoof', 'air.clz.v2i32', 'air.ctz.f32', 'air.clz.s.i32', 'air.cttz.i32'] {
		if _ := scalar_intrinsic_name(name) { assert false, name }
	}
	println('AIR-ZERO-COUNT-NAMES: two exact i32 names, appended slots, i1 flag identity and width/vector/family/spelling guards PASS')
}

fn test_air_integer_extremum_identity() {
	ids := [ScalarIntrinsic.smin, .smax, .umin, .umax]!
	for i, name in ['air.min.s.i32', 'air.max.s.i32', 'air.min.u.i32', 'air.max.u.i32'] {
		id, slot := air_integer_intrinsic(name)!
		assert id == ids[i] && slot == 2 + i && scalar_integer_extremum(id)
		assert scalar_intrinsic_name(name)! == id && scalar_intrinsic_arity(id) == 2
		assert scalar_integer_intrinsic_width(name, id)! == 32
		if _ := scalar_integer_intrinsic_width(name, ids[(i + 1) % 4]) { assert false }
	}
	for name in ['air.min.i32', 'air.max.i32', 'air.min.s.i16', 'air.min.s.i032', 'air.min.s.i+32', 'air.min.s.v2i32', 'air.max.u.f32', 'air.max.u.i32.spoof', 'air.smin.i32', 'air.umax.i32', 'air.min.x.i32'] {
		if _ := scalar_intrinsic_name(name) { assert false, name }
	}
	println('AIR-INTEGER-EXTREMA-NAMES: four exact signed/unsigned i32 names, appended slots, binary identity and width/vector/family/spelling guards PASS')
}

fn test_air_i64_bit_intrinsic_identity() {
	assert scalar_air_i64_integer_cache_base == 2179 && scalar_intrinsic_cache_slots == 2204
	for i, name in ['air.popcount.i64', 'air.reverse_bits.i64'] {
		id, slot := air_integer_intrinsic(name)!
		assert id == if i == 0 { ScalarIntrinsic.ctpop } else { ScalarIntrinsic.bitreverse }
		assert scalar_air_integer_cache_base + slot == 2179 + i
		assert scalar_intrinsic_name(name)! == id && scalar_intrinsic_arity(id) == 1
		assert scalar_integer_intrinsic_width(name, id)! == 64
		assert scalar_integer_intrinsic_value(id, 64, ~u64(0))! == if i == 0 { u64(64) } else { ~u64(0) }
		if _ := scalar_integer_intrinsic_width(name, if i == 0 { ScalarIntrinsic.bitreverse } else { ScalarIntrinsic.ctpop }) { assert false }
	}
	for family in ['popcount', 'reverse_bits'] {
		for suffix in ['i0','i1','i16','i63','i65','i064','i+64','i64.spoof','f64','v2i64','i64.i64'] {
			if _ := scalar_intrinsic_name('air.${family}.${suffix}') { assert false }
		}
	}
	for name in ['air.ctpop.i64','air.fast_popcount.i64'] {
		if _ := scalar_intrinsic_name(name) { assert false }
	}
	println('AIR-I64-BIT-NAMES: two appended scalar identities after AIR floats, stable i32/LLVM/vector keys, exact names/widths/arity and namespace guards PASS')
}

fn test_air_i64_extremum_intrinsic_identity() {
	ids := [ScalarIntrinsic.smin, .smax, .umin, .umax]!
	assert scalar_air_i64_integer_cache_base == 2179 && scalar_intrinsic_cache_slots == 2204
	for i, name in ['air.min.s.i64','air.max.s.i64','air.min.u.i64','air.max.u.i64'] {
		id, slot := air_integer_intrinsic(name)!
		assert id == ids[i] && scalar_air_integer_cache_base + slot == 2181 + i
		assert scalar_intrinsic_name(name)! == id && scalar_intrinsic_arity(id) == 2
		assert scalar_integer_intrinsic_width(name, id)! == 64
		if _ := scalar_integer_intrinsic_width(name, ids[(i + 1) % 4]) { assert false }
		for bad in ['i0','i1','i16','i63','i65','i064','i+64','i64.spoof','f64','v2i64','i64.i64'] {
			stem := ['air.min.s.','air.max.s.','air.min.u.','air.max.u.'][i]
			if _ := scalar_intrinsic_name(stem + bad) { assert false }
		}
	}
	println('AIR-I64-EXTREMA-NAMES: four appended scalar min/max identities, stable old integer/float/LLVM/vector keys, exact names/widths/arity and family guards PASS')
}

fn test_air_i64_zero_count_intrinsic_identity() {
	assert scalar_air_i64_integer_cache_base == 2179 && scalar_intrinsic_cache_slots == 2204
	for i, name in ['air.clz.i64','air.ctz.i64'] {
		id, slot := air_integer_intrinsic(name)!
		assert id == if i == 0 { ScalarIntrinsic.ctlz } else { ScalarIntrinsic.cttz }
		assert scalar_air_integer_cache_base + slot == 2185 + i
		assert scalar_intrinsic_name(name)! == id && scalar_intrinsic_arity(id) == 2 && scalar_integer_poison_flag(id)
		assert scalar_integer_intrinsic_width(name, id)! == 64
		assert scalar_integer_zero_count_value(id, 64, 0, 0)!.value == 64
		assert scalar_integer_zero_count_value(id, 64, u64(1) << 63, 0)!.value == if i == 0 { u64(0) } else { u64(63) }
		if _ := scalar_integer_intrinsic_width(name, .ctpop) { assert false }
		for suffix in ['i0','i1','i16','i63','i65','i064','i+64','i64.spoof','f64','v2i64','i64.i64'] {
			stem := if i == 0 { 'air.clz.' } else { 'air.ctz.' }
			if _ := scalar_intrinsic_name(stem + suffix) { assert false }
		}
	}
	println('AIR-I64-ZERO-COUNT-NAMES: two appended scalar identities, stable old keys, exact names/widths/arity, zero/sign boundaries and family guards PASS')
}

fn test_air_i64_saturating_intrinsic_identity() {
	ids := [ScalarIntrinsic.sadd_sat, .ssub_sat, .uadd_sat, .usub_sat]!
	assert scalar_air_i64_integer_cache_base == 2179 && scalar_intrinsic_cache_slots == 2204
	for i, name in ['air.add_sat.s.i64','air.sub_sat.s.i64','air.add_sat.u.i64','air.sub_sat.u.i64'] {
		id, slot := air_integer_intrinsic(name)!
		assert id == ids[i] && scalar_air_integer_cache_base + slot == 2187 + i && scalar_integer_saturating(id)
		assert scalar_intrinsic_name(name)! == id && scalar_intrinsic_arity(id) == 2
		assert scalar_integer_intrinsic_width(name, id)! == 64
		if _ := scalar_integer_intrinsic_width(name, ids[(i + 1) % 4]) { assert false }
		for bad in ['i0','i1','i16','i63','i65','i064','i+64','i64.spoof','f64','v2i64','i64.i64'] {
			stem := ['air.add_sat.s.','air.sub_sat.s.','air.add_sat.u.','air.sub_sat.u.'][i]
			if _ := scalar_intrinsic_name(stem + bad) { assert false }
		}
	}
	assert scalar_integer_saturating_value(.sadd_sat,64,0x7fffffffffffffff,1)! == 0x7fffffffffffffff
	assert scalar_integer_saturating_value(.sadd_sat,64,0x8000000000000000,~u64(0))! == 0x8000000000000000
	assert scalar_integer_saturating_value(.ssub_sat,64,0x8000000000000000,1)! == 0x8000000000000000
	assert scalar_integer_saturating_value(.ssub_sat,64,0x7fffffffffffffff,~u64(0))! == 0x7fffffffffffffff
	assert scalar_integer_saturating_value(.uadd_sat,64,~u64(0),1)! == ~u64(0)
	assert scalar_integer_saturating_value(.usub_sat,64,0,1)! == 0
	println('AIR-I64-SATURATING-NAMES: four appended scalar identities, stable old keys, exact names/widths/arity, saturation endpoints and family guards PASS')
}

fn test_air_i64_multiply_high_intrinsic_identity() {
	assert scalar_air_i64_integer_cache_base == 2179 && scalar_intrinsic_cache_slots == 2204
	for i, name in ['air.mul_hi.s.i64','air.mul_hi.u.i64'] {
		id, slot := air_integer_intrinsic(name)!
		assert id == if i == 0 { ScalarIntrinsic.smulh } else { ScalarIntrinsic.umulh }
		assert scalar_air_integer_cache_base + slot == 2191 + i && scalar_integer_mulh(id)
		assert scalar_intrinsic_name(name)! == id && scalar_intrinsic_arity(id) == 2
		assert scalar_integer_intrinsic_width(name, id)! == 64
		if _ := scalar_integer_intrinsic_width(name, .ctpop) { assert false }
		for bad in ['i0','i1','i16','i63','i65','i064','i+64','i64.spoof','f64','v2i64','i64.i64'] {
			stem := if i == 0 { 'air.mul_hi.s.' } else { 'air.mul_hi.u.' }
			if _ := scalar_intrinsic_name(stem + bad) { assert false }
		}
	}
	assert scalar_integer_mulh_value(.smulh,64,~u64(0),~u64(0))! == 0
	assert scalar_integer_mulh_value(.umulh,64,~u64(0),~u64(0))! == ~u64(1)
	assert scalar_integer_mulh_value(.smulh,64,0x8000000000000000,~u64(0))! == 0
	assert scalar_integer_mulh_value(.umulh,64,0x8000000000000000,~u64(0))! == 0x7fffffffffffffff
	println('AIR-I64-MULH-NAMES: two appended scalar identities, stable old keys, exact names/widths/arity, high-word boundaries and family guards PASS')
}
