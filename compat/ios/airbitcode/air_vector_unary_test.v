// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_air_vector_unary_names_and_keys() {
	assert vector_air_unary_cache_base == 61604 && vector_float_intrinsic_slots == 61940 && scalar_intrinsic_cache_slots == 2179
	mut seen := [112]bool{}
	for operation, id in [ScalarIntrinsic.fabs, .floor, .ceil, .trunc, .sqrt, .round, .rint]! { for count in 1 .. 17 {
		name := 'air.${id}.v${count}f32'
		parsed, lanes, bits := vector_float_intrinsic_name(name)!
		assert parsed == id && lanes == count && bits == 32 && scalar_intrinsic_arity(id) == 1
		key := air_vector_unary_key(parsed, lanes, bits)!
		assert key == 61604 + operation * 16 + count - 1 && !seen[key - 61604]; seen[key - 61604] = true
		assert vector_float_intrinsic_key(id, count, bits)! < 61604
		if _ := scalar_intrinsic_name(name) { assert false, 'vector as scalar' }
	} }
	for value in seen { assert value }
	for operation in ['fabs','floor','ceil','trunc','sqrt','round','rint'] {
		for suffix in ['f32','v0f32','v01f32','v17f32','v999999999999999999f32','v2f16','v2f64','v2i32','v2bf16','v2f032','v2f+32','v2f32.spoof','nxv2f32'] {
			if _, _, _ := vector_float_intrinsic_name('air.${operation}.${suffix}') { assert false }
		}
		if _, _, _ := vector_float_intrinsic_name('air.fast_${operation}.v2f32') { assert false }
	}
	for name in ['air.roundeven.v2f32','air.nearbyint.v2f32','air.fma.v2f16','air.clamp.v2f16','air.copysign.v2f32'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false } }
	for id in [ScalarIntrinsic.copysign, .fma, .air_fmin, .air_clamp]! { if _ := air_vector_unary_key(id, 2, 32) { assert false } }
	for bits in [u32(16),64]! { if _ := air_vector_unary_key(.sqrt, 2, bits) { assert false } }
	for count in [0,17]! { if _ := air_vector_unary_key(.sqrt, count, 32) { assert false } }
	println('AIR-VECTOR-UNARY-NAMES: 112 distinct appended AIR keys, unchanged LLVM keys, exact names/arity/width/lane bounds and scalar isolation PASS')
}
