// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn clamp_reference_number(minimum bool, a u32, b u32) u32 {
	xnan := a & 0x7fffffff > 0x7f800000; ynan := b & 0x7fffffff > 0x7f800000
	if xnan && ynan { return 0x7fc00000 }; if xnan { return b }; if ynan { return a }
	if a & 0x7fffffff == 0 && b & 0x7fffffff == 0 { return a }
	xkey := if a >> 31 != 0 { ~a } else { a | u32(0x80000000) }; ykey := if b >> 31 != 0 { ~b } else { b | u32(0x80000000) }
	return if (xkey < ykey) == minimum { a } else { b }
}

fn test_air_vector_clamp_values_states_and_cache() {
	assert vector_air_clamp_cache_base == 61764 && vector_float_intrinsic_slots == 61972 && scalar_intrinsic_cache_slots == 2179
	edges := [u32(0),0x80000000,1,0x80000001,0x007fffff,0x807fffff,0x00800000,0x80800000,0x3f800000,0xbf800000,0x3f800001,0xbf800001,0x7f7fffff,0xff7fffff,0x7f800000,0xff800000,0x7f800001,0xff800001,0x7fc00000,0xffc00000,0x7fc12345,0xffc12345,0x3f000000,0xbf000000]!
	mut checks := 0; mut states := 0; mut seen := [16]bool{}
	for count in 1 .. 17 {
		name := 'air.clamp.v${count}f32'; id, n, bits := vector_float_intrinsic_name(name)!
		assert id == .air_clamp && n == count && bits == 32 && scalar_intrinsic_arity(id) == 3
		key := air_vector_float_key(id, count, bits)!; assert key == 61764 + count - 1 && !seen[key - 61764]; seen[key - 61764] = true
		if _ := scalar_intrinsic_name(name) { assert false }
		for sample in 0 .. 16384 {
			mut sources := [3]ScalarVectorValue{}
			for side in 0 .. 3 { for lane in 0 .. count {
				divisor := if side == 0 { 576 } else if side == 1 { 24 } else { 1 }
				value := if sample < 13824 { edges[(sample / divisor + lane) % 24] } else { u32(sample) * u32(0x9e3779b9) ^ u32(lane + side) * u32(0x85ebca6b) }
				sources[side].lanes[lane] = IntegerValue{value: u64(value) | u64(0xabcdef01 + side) << 32}
			} }
			before := sources; result := air_clamp_vector(sources[0], sources[1], sources[2], 32, count)!
			for lane in 0 .. count {
				x := u32(sources[0].lanes[lane].value); low := u32(sources[1].lanes[lane].value); high := u32(sources[2].lanes[lane].value)
				ordered := low & 0x7fffffff <= 0x7f800000 && high & 0x7fffffff <= 0x7f800000
				unequal := low != high && !(low & 0x7fffffff == 0 && high & 0x7fffffff == 0)
				invalid := ordered && unequal && clamp_reference_number(false, low, high) == low
				assert result.lanes[lane] == if invalid { IntegerValue{poison: true} } else { IntegerValue{value: clamp_reference_number(true, clamp_reference_number(false, x, low), high)} }
				checks++
			}
			assert sources == before && result.undef == 0
		}
		for side in 0 .. 3 { for target in 0 .. count {
			mut sources := [3]ScalarVectorValue{}
			for s in 0 .. 3 { for lane in 0 .. count { sources[s].lanes[lane] = IntegerValue{value: 0x7fc12345} } }
			sources[side].lanes[target] = IntegerValue{poison: true}
			result := air_clamp_vector(sources[0], sources[1], sources[2], 32, count)!
			for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); states++ }
			assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
			sources[side].undef = u16(1) << u32(target)
			if _ := air_clamp_vector(sources[0], sources[1], sources[2], 32, count) { assert false }; states++
		} }
	}
	for slot in seen { assert slot }
	for suffix in ['f32','v0f32','v01f32','v17f32','v999999999999999999f32','v2f16','v2f64','v2i32','v2bf16','v2f032','v2f+32','v2f32.spoof','nxv2f32'] { if _, _, _ := vector_float_intrinsic_name('air.clamp.${suffix}') { assert false } }
	for name in ['air.fast_clamp.v2f32','air.saturate.v2f32','llvm.clamp.v2f32'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false } }
	for id in [ScalarIntrinsic.fma,.air_fmin,.air_fmax]! { if _ := air_vector_clamp_key(id, 2, 32) { assert false } }
	for bits in [u32(16),64]! { if _ := air_clamp_vector(ScalarVectorValue{}, ScalarVectorValue{}, ScalarVectorValue{}, bits, 1) { assert false } }
	for count in [0,17]! { if _ := air_clamp_vector(ScalarVectorValue{}, ScalarVectorValue{}, ScalarVectorValue{}, 32, count) { assert false } }
	for side in 0 .. 3 { for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut sources := [3]ScalarVectorValue{}; sources[side].lanes[0] = tag; if _ := air_clamp_vector(sources[0], sources[1], sources[2], 32, 1) { assert false } } }
	assert checks == 2228224 && states == 4896
	println('AIR-VECTOR-CLAMP-UNIT: ${checks} independent ordered-key lanes, ${states} three-source poison/undef states with NaN peers, snapshots, 16 appended keys and exact family/width/count/name/tag guards PASS')
}
