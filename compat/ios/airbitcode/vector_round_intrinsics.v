// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn vector_round_intrinsic_index(id ScalarIntrinsic) !int {
	return match id { .floor { 0 } .ceil { 1 } .trunc { 2 } .round { 3 } .roundeven { 4 } .rint { 5 } .nearbyint { 6 } else { return error('AIR vector intrinsic: rounding family') } }
}
// Only canonical fixed half/float overloads; no allocation on the call path.
fn vector_round_intrinsic_name(name string) !(ScalarIntrinsic, int, u32) {
	mut id := ScalarIntrinsic.floor
	mut offset := 0
	if name.starts_with('llvm.floor.v') { offset = 12 }
	else if name.starts_with('llvm.ceil.v') { id = .ceil; offset = 11 }
	else if name.starts_with('llvm.trunc.v') { id = .trunc; offset = 12 }
	else if name.starts_with('llvm.round.v') { id = .round; offset = 12 }
	else if name.starts_with('llvm.roundeven.v') { id = .roundeven; offset = 16 }
	else if name.starts_with('llvm.rint.v') { id = .rint; offset = 11 }
	else if name.starts_with('llvm.nearbyint.v') { id = .nearbyint; offset = 16 }
	else { return error('AIR vector intrinsic: unsupported name') }
	count, bits := vector_float_overload(name, offset)!
	return id, count, bits
}
fn vector_float_intrinsic_name(name string) !(ScalarIntrinsic, int, u32) {
	if name.starts_with('air.') { return air_vector_float_name(name) }
	if name.starts_with('llvm.vector.insert.') { count, _, format := vector_subinsert_name(name)!; return ScalarIntrinsic.vector_insert, count, if format < 64 { u32(format + 1) } else if format == 64 { u32(16) } else { u32(32) } }
	if name.starts_with('llvm.vector.extract.') { count, _, format := vector_subvector_name(name)!; return ScalarIntrinsic.vector_extract, count, if format < 64 { u32(format + 1) } else if format == 64 { u32(16) } else { u32(32) } }
	if name.starts_with('llvm.get.active.lane.mask.') { count, _ := vector_active_mask_name(name)!; return ScalarIntrinsic.active_lane_mask, count, u32(1) }
	if name.starts_with('llvm.stepvector.') { count, bits := vector_step_name(name)!; return ScalarIntrinsic.stepvector, count, bits }
	if name.starts_with('llvm.vector.interleave') { id, count, format := vector_interleave_name(name)!; return id, count, if format < 64 { u32(format + 1) } else if format == 64 { u32(16) } else { u32(32) } }
	if name.starts_with('llvm.vector.splice.') { id, count, format := vector_splice_name(name)!; return id, count, if format < 64 { u32(format + 1) } else if format == 64 { u32(16) } else { u32(32) } }
	if name.starts_with('llvm.vector.reverse.') { count, format := vector_reverse_name(name)!; return ScalarIntrinsic.vector_reverse, count, if format < 64 { u32(format + 1) } else if format == 64 { u32(16) } else { u32(32) } }
	if name.starts_with('llvm.smulh.v') || name.starts_with('llvm.umulh.v') { count, bits := vector_integer_overload(name, 12)!; return if name[5] == `s` { ScalarIntrinsic.smulh } else { ScalarIntrinsic.umulh }, count, bits }
	if name.starts_with('llvm.canonicalize.v') { count, bits := vector_float_overload(name, 19)!; return ScalarIntrinsic.canonicalize, count, bits }
	if name.starts_with('llvm.clmul.v') { count, bits := vector_integer_overload(name, 12)!; return ScalarIntrinsic.clmul, count, bits }
	if name.starts_with('llvm.pext.v') || name.starts_with('llvm.pdep.v') { count, bits := vector_integer_overload(name, 11)!; return if name[6] == `e` { ScalarIntrinsic.pext } else { ScalarIntrinsic.pdep }, count, bits }
	if name.starts_with('llvm.fptosi.sat.v') || name.starts_with('llvm.fptoui.sat.v') {
		id, count, _, dest := vector_saturating_cast_name(name)!
		return id, count, dest
	}
	if name.starts_with('llvm.sshl.sat.v') || name.starts_with('llvm.ushl.sat.v') {
		count, bits := vector_integer_overload(name, 15)!
		return if name[5] == `s` { ScalarIntrinsic.sshl_sat } else { ScalarIntrinsic.ushl_sat }, count, bits
	}
 for id in [ScalarIntrinsic.sadd_sat,.uadd_sat,.ssub_sat,.usub_sat]! {
  prefix:=match id{.sadd_sat{'llvm.sadd.sat.v'} .uadd_sat{'llvm.uadd.sat.v'} .ssub_sat{'llvm.ssub.sat.v'} else{'llvm.usub.sat.v'}}
  if name.starts_with(prefix){count,bits:=vector_integer_overload(name,15)!;return id,count,bits}
 }
	if name.starts_with('llvm.abs.v') { count, bits := vector_integer_overload(name, 10)!; return ScalarIntrinsic.iabs, count, bits }
 for id in [ScalarIntrinsic.smin, .smax, .umin, .umax]! {
  prefix := match id {.smin {'llvm.smin.v'} .smax {'llvm.smax.v'} .umin {'llvm.umin.v'} else {'llvm.umax.v'}}
  if name.starts_with(prefix) {count,bits:=vector_integer_overload(name,11)!;return id,count,bits}
 }
	if name.starts_with('llvm.fshl.v') || name.starts_with('llvm.fshr.v') { count, bits := vector_integer_overload(name, 11)!; return if name[8] == `l` { ScalarIntrinsic.fshl } else { ScalarIntrinsic.fshr }, count, bits }
	if name.starts_with('llvm.cttz.v') { count, bits := vector_integer_overload(name, 11)!; return ScalarIntrinsic.cttz, count, bits }
	if name.starts_with('llvm.ctlz.v') { count, bits := vector_integer_overload(name, 11)!; return ScalarIntrinsic.ctlz, count, bits }
	if name.starts_with('llvm.bswap.v') { count, bits := vector_integer_overload(name, 12)!; if bits % 16 != 0 { return error('AIR vector intrinsic: even byte width required') }; return ScalarIntrinsic.bswap, count, bits }
	if name.starts_with('llvm.bitreverse.v') { count, bits := vector_integer_overload(name, 17)!; return ScalarIntrinsic.bitreverse, count, bits }
	if name.starts_with('llvm.ctpop.v') { count, bits := vector_integer_overload(name, 12)!; return ScalarIntrinsic.ctpop, count, bits }
	if name.starts_with('llvm.is.fpclass.v') { count, bits := vector_float_overload(name, 17)!; return ScalarIntrinsic.is_fpclass, count, bits }
	if name.starts_with('llvm.ldexp.') { return vector_ldexp_intrinsic_name(name) }
	if name.starts_with('llvm.fmuladd.v') { count, bits := vector_float_overload(name, 14)!; return ScalarIntrinsic.fmuladd, count, bits }
	if name.starts_with('llvm.fma.v') { count, bits := vector_float_overload(name, 10)!; return ScalarIntrinsic.fma, count, bits }
	if name.starts_with('llvm.fabs.') || name.starts_with('llvm.copysign.') { return vector_sign_intrinsic_name(name) }
	if name.starts_with('llvm.sqrt.v') { count, bits := vector_float_overload(name, 11)!; return ScalarIntrinsic.sqrt, count, bits }
	if name.starts_with('llvm.min') || name.starts_with('llvm.max') { return vector_minmax_intrinsic_name(name) }
	return vector_round_intrinsic_name(name)
}
fn vector_float_intrinsic_key(id ScalarIntrinsic, count int, bits u32) !int {
	if scalar_integer_mulh(id) {
		if count < 1 || count > 16 || bits < 1 || bits > 64 { return error('AIR vector intrinsic: cache shape') }
		return vector_mulh_cache_base + int(id == .umulh) * 1024 + int(bits - 1) * 16 + count - 1
	}
	if id == .canonicalize {
		if count < 1 || count > 16 || bits !in [u32(16), 32]! { return error('AIR vector intrinsic: cache shape') }
		return vector_canonicalize_cache_base + int(bits == 16) * 16 + count - 1
	}
	if id == .clmul {
		if count < 1 || count > 16 || bits < 1 || bits > 64 { return error('AIR vector intrinsic: cache shape') }
		return vector_clmul_cache_base + int(bits - 1) * 16 + count - 1
	}
	if scalar_integer_bit_permutation(id) {
		if count < 1 || count > 16 || bits < 1 || bits > 64 { return error('AIR vector intrinsic: cache shape') }
		return 22208 + int(id == .pdep) * 1024 + int(bits - 1) * 16 + count - 1
	}
	if scalar_integer_saturating_shift(id) {
		if count < 1 || count > 16 || bits < 1 || bits > 64 { return error('AIR vector intrinsic: cache shape') }
		return 16064 + vector_saturating_shift_index(id)! * 1024 + int(bits - 1) * 16 + count - 1
	}
 if scalar_integer_saturating(id) {
  if count<1||count>16||bits<1||bits>64{return error('AIR vector intrinsic: cache shape')}
  return 11968+vector_saturating_index(id)!*1024+int(bits-1)*16+count-1
 }
	if id == .iabs {
		if count < 1 || count > 16 || bits < 1 || bits > 64 { return error('AIR vector intrinsic: cache shape') }
		return 10944 + int(bits - 1) * 16 + count - 1
	}
	if scalar_integer_extremum(id) {
		if count < 1 || count > 16 || bits < 1 || bits > 64 { return error('AIR vector intrinsic: cache shape') }
		return 6848 + vector_integer_extremum_index(id)! * 1024 + int(bits - 1) * 16 + count - 1
	}
	if scalar_integer_funnel(id) {
		if count < 1 || count > 16 || bits < 1 || bits > 64 { return error('AIR vector intrinsic: cache shape') }
		return 4800 + int(id == .fshr) * 1024 + int(bits - 1) * 16 + count - 1
	}
	if id in [.ctlz, .cttz]! {
		if count < 1 || count > 16 || bits < 1 || bits > 64 { return error('AIR vector intrinsic: cache shape') }
		return 2752 + int(id == .cttz) * 1024 + int(bits - 1) * 16 + count - 1
	}
	if id == .bswap {
		if count < 1 || count > 16 || bits < 16 || bits > 64 || bits % 16 != 0 { return error('AIR vector intrinsic: cache shape') }
		return 2688 + int(bits / 16 - 1) * 16 + count - 1
	}
	if id in [.ctpop, .bitreverse]! {
		if count < 1 || count > 16 || bits < 1 || bits > 64 { return error('AIR vector intrinsic: cache shape') }
		return 640 + int(id == .bitreverse) * 1024 + int(bits - 1) * 16 + count - 1
	}
	if id in [.ldexp, .is_fpclass]! {
		if count < 1 || count > 16 || bits !in [u32(16), 32]! { return error('AIR vector intrinsic: cache shape') }
		return 576 + int(id == .is_fpclass) * 32 + int(bits == 16) * 16 + count - 1
	}
	if id in [.fma, .fmuladd]! {
		if count < 1 || count > 16 || bits !in [u32(16), 32]! { return error('AIR vector intrinsic: cache shape') }
		return 512 + int(id == .fmuladd) * 32 + int(bits == 16) * 16 + count - 1
	}
	if id in [.fabs, .copysign]! { return vector_sign_intrinsic_key(id, count, bits) }
	if id in [.minimum, .maximum, .minimumnum, .maximumnum, .minnum, .maxnum]! {
		if count < 1 || count > 16 || bits !in [u32(16), 32]! { return error('AIR vector intrinsic: cache shape') }
		return vector_sign_intrinsic_slots + 224 + 32 + vector_minmax_intrinsic_index(id)! * 32 + int(bits == 16) * 16 + count - 1
	}
	if id == .sqrt {
		if count < 1 || count > 16 || bits !in [u32(16), 32]! { return error('AIR vector intrinsic: cache shape') }
		return vector_sign_intrinsic_slots + 224 + int(bits == 16) * 16 + count - 1
	}
	operation := vector_round_intrinsic_index(id)!
	if count < 1 || count > 16 || bits !in [u32(16), 32]! { return error('AIR vector intrinsic: cache shape') }
	return vector_sign_intrinsic_slots + operation * 32 + int(bits == 16) * 16 + count - 1
}
fn rounding_intrinsic_vector(id ScalarIntrinsic, source ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
	vector_round_intrinsic_index(id)!
	vector_float_intrinsic_key(id, count, bits)!
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		a := source.lanes[lane]
		if source.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector intrinsic: undef source lane') }
		if a.aggregate || a.vector { return error('AIR vector intrinsic: scalar lanes required') }
		result.lanes[lane] = if a.poison { IntegerValue{poison: true} } else { IntegerValue{value: scalar_intrinsic_value(id, bits, a.value, 0)!} }
	}
	return result
}
