// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn air_vector_number_reference(minimum bool, a u32, b u32) u32 {
	xnan := a & 0x7fffffff > 0x7f800000; ynan := b & 0x7fffffff > 0x7f800000
	if xnan && ynan { return 0x7fc00000 }; if xnan { return b }; if ynan { return a }
	if a & 0x7fffffff == 0 && b & 0x7fffffff == 0 { return a }
	xkey := if a >> 31 != 0 { ~a } else { a | u32(0x80000000) }; ykey := if b >> 31 != 0 { ~b } else { b | u32(0x80000000) }
	return if (xkey < ykey) == minimum { a } else { b }
}

fn test_air_vector_extrema_values_states_names_and_keys() {
	assert vector_air_extrema_cache_base == 61732 && vector_float_intrinsic_slots == 62004 && scalar_intrinsic_cache_slots == 2179
	edges := [u32(0),0x80000000,1,0x80000001,0x007fffff,0x807fffff,0x00800000,0x80800000,0x3f800000,0xbf800000,0x3f800001,0xbf800001,0x7f7fffff,0xff7fffff,0x7f800000,0xff800000,0x7f800001,0xff800001,0x7fc00000,0xffc00000,0x7fc12345,0xffc12345,0x3f000000,0xbf000000]!
	mut checks := 0; mut states := 0; mut seen := [32]bool{}
	for operation, id in [ScalarIntrinsic.air_fmin, .air_fmax]! { for count in 1 .. 17 {
		name := 'air.${if operation == 0 {'fmin'} else {'fmax'}}.v${count}f32'; parsed, n, bits := vector_float_intrinsic_name(name)!
		assert parsed == id && n == count && bits == 32 && scalar_intrinsic_arity(id) == 2
		key := air_vector_float_key(id, count, 32)!; assert key == 61732 + operation * 16 + count - 1 && !seen[key - 61732]; seen[key - 61732] = true
		if _ := scalar_intrinsic_name(name) { assert false }
		for sample in 0 .. 8192 {
			mut left := ScalarVectorValue{}; mut right := ScalarVectorValue{}
			for lane in 0 .. count {
				x := if sample < 576 { edges[(sample / 24 + lane) % 24] } else { u32(sample) * u32(0x9e3779b9) + u32(lane) }
				y := if sample < 576 { edges[(sample + lane) % 24] } else if sample % 4 == 0 { x } else { u32(sample) * u32(0x85ebca6b) ^ u32(lane) * u32(0xa5a5a5a5) }
				left.lanes[lane] = IntegerValue{value: u64(x) | u64(0x12345678) << 32}; right.lanes[lane] = IntegerValue{value: u64(y) | u64(0x87654321) << 32}
			}
			before_left := left; before_right := right; result := air_extrema_vector(id, left, right, 32, count)!
			for lane in 0 .. count { assert result.lanes[lane] == IntegerValue{value: air_vector_number_reference(operation == 0, u32(left.lanes[lane].value), u32(right.lanes[lane].value))}; checks++ }
			assert left == before_left && right == before_right && result.undef == 0
		}
		for side in 0 .. 2 { for target in 0 .. count {
			mut left := ScalarVectorValue{}; mut right := ScalarVectorValue{}
			for lane in 0 .. count { left.lanes[lane] = IntegerValue{value: 0x7fc12345}; right.lanes[lane] = IntegerValue{value: 0x7fc12345} }
			if side == 0 { left.lanes[target] = IntegerValue{poison: true} } else { right.lanes[target] = IntegerValue{poison: true} }
			result := air_extrema_vector(id, left, right, 32, count)!; for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); states++ }; assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
			if side == 0 { left.undef = u16(1) << u32(target) } else { right.undef = u16(1) << u32(target) }; if _ := air_extrema_vector(id, left, right, 32, count) { assert false }; states++
		} }
	} }
	for slot in seen { assert slot }
	for prefix in ['fmin','fmax'] { for suffix in ['f32','v0f32','v01f32','v17f32','v999999999999999999f32','v2f16','v2f64','v2i32','v2bf16','v2f032','v2f+32','v2f32.spoof','nxv2f32'] { if _, _, _ := vector_float_intrinsic_name('air.${prefix}.${suffix}') { assert false } }; if _, _, _ := vector_float_intrinsic_name('air.fast_${prefix}.v2f32') { assert false } }
	for name in ['air.min.v2f32','air.minnum.v2f32','air.fast_clamp.v2f32'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false } }
	for bits in [u32(16),64]! { if _ := air_extrema_vector(.air_fmin, ScalarVectorValue{}, ScalarVectorValue{}, bits, 1) { assert false } }
	for count in [0,17]! { if _ := air_extrema_vector(.air_fmin, ScalarVectorValue{}, ScalarVectorValue{}, 32, count) { assert false } }
	for id in [ScalarIntrinsic.minnum,.maxnum,.fma]! { if _ := air_extrema_vector(id, ScalarVectorValue{}, ScalarVectorValue{}, 32, 1) { assert false } }
	for side in 0 .. 2 { for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := air_extrema_vector(.air_fmin, if side == 0 { source } else { ScalarVectorValue{} }, if side == 1 { source } else { ScalarVectorValue{} }, 32, 1) { assert false } } }
	assert checks == 2228224 && states == 6528
	println('AIR-VECTOR-EXTREMA-UNIT: ${checks} independent ordered-key lanes, ${states} poison/undef states with NaN peers, snapshots, first signed zeros, 32 appended keys and exact family/width/count/name/tag guards PASS')
}
