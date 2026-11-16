// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_air_vector_integer_names_and_cache() {
	assert vector_air_integer_cache_base == 61780 && vector_float_intrinsic_slots == 61812 && scalar_intrinsic_cache_slots == 2179
	mut seen := [32]bool{}
	for operation, id in [ScalarIntrinsic.smulh, .umulh]! { for count in 1 .. 17 {
		name := 'air.mul_hi.${if operation == 0 { 's' } else { 'u' }}.v${count}i32'
		parsed, lanes, bits := vector_float_intrinsic_name(name)!
		assert parsed == id && lanes == count && bits == 32 && scalar_intrinsic_arity(id) == 2
		key := air_vector_intrinsic_key(id, count, bits)!
		assert key == 61780 + operation * 16 + count - 1 && !seen[key - 61780]; seen[key - 61780] = true
		assert vector_float_intrinsic_key(id, count, bits)! < 61604
		if _ := scalar_intrinsic_name(name) { assert false }
		if _, _, _ := air_vector_float_name(name) { assert false }
		if _ := air_vector_float_key(id, count, bits) { assert false }
	} }
	for value in seen { assert value }
	for sign in ['s', 'u'] {
		for suffix in ['i32','v0i32','v01i32','v17i32','v999999999999999999i32','v2i1','v2i16','v2i31','v2i33','v2i64','v2i032','v2i+32','v2f32','v2i32.spoof','nxv2i32'] {
			if _, _, _ := vector_float_intrinsic_name('air.mul_hi.${sign}.${suffix}') { assert false }
		}
	}
	for name in ['air.mul_hi.v2i32','air.mul_hi.x.v2i32','air.smulh.v2i32','air.umulh.v2i32','air.mul_hi.s.u.v2i32','air.min.s.v2i32','air.popcount.v2i32','air.fast_mul_hi.s.v2i32'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false } }
	for id in [ScalarIntrinsic.clmul, .smin, .fabs, .air_clamp]! { if _ := air_vector_integer_key(id, 2, 32) { assert false } }
	for bits in [u32(0),1,16,31,33,64,65]! { if _ := air_vector_intrinsic_key(.smulh, 2, bits) { assert false } }
	for count in [0,17]! { if _ := air_vector_intrinsic_key(.umulh, count, 32) { assert false } }
	for id in [ScalarIntrinsic.fabs, .floor, .ceil, .trunc, .sqrt, .round, .rint, .fma, .air_fmin, .air_fmax, .air_clamp]! { for count in 1 .. 17 { assert air_vector_intrinsic_key(id, count, 32)! == air_vector_float_key(id, count, 32)! } }
	println('AIR-VECTOR-INTEGER-NAMES: 32 appended signed/unsigned i32 multiply-high identities, unchanged LLVM/float/scalar keys, exact names/signs/arity/width/count and namespace guards PASS')
}
