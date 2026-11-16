// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_air_vector_fma_names_and_cache() {
	assert vector_air_fma_cache_base == 61716 && vector_float_intrinsic_slots == 61780 && scalar_intrinsic_cache_slots == 2179
	for count in 1 .. 17 {
		name := 'air.fma.v${count}f32'; id, n, bits := vector_float_intrinsic_name(name)!
		assert id == .fma && n == count && bits == 32 && scalar_intrinsic_arity(id) == 3
		assert air_vector_float_key(id, n, bits)! == 61716 + count - 1
		assert vector_float_intrinsic_key(id, n, bits)! == 512 + count - 1
		if _ := scalar_intrinsic_name(name) { assert false, 'vector as scalar' }
		if _, _, _ := air_vector_unary_name(name) { assert false, 'ternary as unary' }
	}
	for suffix in ['f32','v0f32','v01f32','v17f32','v999999999999999999f32','v2f16','v2f64','v2i32','v2bf16','v2f032','v2f+32','v2f32.spoof','nxv2f32'] { if _, _, _ := vector_float_intrinsic_name('air.fma.${suffix}') { assert false } }
	for name in ['air.fast_fma.v2f32','air.fmuladd.v2f32'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false } }
	for bits in [u32(16),64]! { if _ := air_vector_float_key(.fma, 2, bits) { assert false } }
	for count in [0,17]! { if _ := air_vector_float_key(.fma, count, 32) { assert false } }
	for id in [ScalarIntrinsic.fabs, .floor, .ceil, .trunc, .sqrt, .round, .rint]! { for count in 1 .. 17 { assert air_vector_float_key(id, count, 32)! == air_vector_unary_key(id, count, 32)! } }
	println('AIR-VECTOR-FMA-NAMES: 16 appended ternary f32 keys, unchanged LLVM/unary keys, exact widths/counts/names and scalar/unary isolation PASS')
}
