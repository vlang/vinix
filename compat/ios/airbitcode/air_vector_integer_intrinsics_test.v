// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_air_vector_integer_names_and_cache() {
	assert vector_air_integer_cache_base == 61780 && vector_float_intrinsic_slots == 62036 && scalar_intrinsic_cache_slots == 2179
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
	for name in ['air.mul_hi.v2i32','air.mul_hi.x.v2i32','air.smulh.v2i32','air.umulh.v2i32','air.mul_hi.s.u.v2i32','air.min.x.v2i32','air.ctpop.v2i32','air.fast_mul_hi.s.v2i32'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false } }
	for id in [ScalarIntrinsic.clmul, .iabs, .fabs, .air_clamp]! { if _ := air_vector_integer_key(id, 2, 32) { assert false } }
	for bits in [u32(0),1,16,31,33,64,65]! { if _ := air_vector_intrinsic_key(.smulh, 2, bits) { assert false } }
	for count in [0,17]! { if _ := air_vector_intrinsic_key(.umulh, count, 32) { assert false } }
	for id in [ScalarIntrinsic.fabs, .floor, .ceil, .trunc, .sqrt, .round, .rint, .fma, .air_fmin, .air_fmax, .air_clamp]! { for count in 1 .. 17 { assert air_vector_intrinsic_key(id, count, 32)! == air_vector_float_key(id, count, 32)! } }
	println('AIR-VECTOR-INTEGER-NAMES: 32 appended signed/unsigned i32 multiply-high identities, unchanged LLVM/float/scalar keys, exact names/signs/arity/width/count and namespace guards PASS')
}

fn test_air_vector_saturating_names_and_cache() {
	mut seen := [64]bool{}
	for operation, id in [ScalarIntrinsic.sadd_sat, .ssub_sat, .uadd_sat, .usub_sat]! {
		family := if id in [.sadd_sat, .uadd_sat]! { 'add_sat' } else { 'sub_sat' }
		sign := if id in [.sadd_sat, .ssub_sat]! { 's' } else { 'u' }
		for count in 1 .. 17 {
			name := 'air.${family}.${sign}.v${count}i32'; parsed, n, bits := vector_float_intrinsic_name(name)!
			assert parsed == id && n == count && bits == 32 && scalar_intrinsic_arity(id) == 2
			key := air_vector_intrinsic_key(id, count, bits)!
			assert key == 61812 + operation * 16 + count - 1 && !seen[key - 61812]; seen[key - 61812] = true
			assert vector_float_intrinsic_key(id, count, bits)! < 61604
			if _ := scalar_intrinsic_name(name) { assert false }
			if _, _, _ := air_vector_float_name(name) { assert false }
			if _ := air_vector_float_key(id, count, bits) { assert false }
		}
		for suffix in ['i32','v0i32','v01i32','v17i32','v999999999999999999i32','v2i1','v2i16','v2i31','v2i33','v2i64','v2i032','v2i+32','v2f32','v2i32.spoof','nxv2i32'] {
			if _, _, _ := vector_float_intrinsic_name('air.${family}.${sign}.${suffix}') { assert false }
		}
		for spelling in ['air.${family}.v2i32','air.${family}.x.v2i32','air.${family}.${sign}.u.v2i32','air.fast_${family}.${sign}.v2i32'] { if _, _, _ := vector_float_intrinsic_name(spelling) { assert false } }
		for bits in [u32(0),1,16,31,33,64,65]! { if _ := air_vector_intrinsic_key(id, 2, bits) { assert false } }
		for count in [0,17]! { if _ := air_vector_intrinsic_key(id, count, 32) { assert false } }
	}
	for value in seen { assert value }
	println('AIR-VECTOR-SATURATING-NAMES: 64 appended signed/unsigned i32 add/sub identities, stable previous keys, exact names/signs/arity/width/count and namespace guards PASS')
}

fn test_air_vector_integer_extrema_names_and_cache() {
	mut seen := [64]bool{}
	for operation, id in [ScalarIntrinsic.smin, .smax, .umin, .umax]! {
		family := if id in [.smin, .umin]! { 'min' } else { 'max' }
		sign := if id in [.smin, .smax]! { 's' } else { 'u' }
		for count in 1 .. 17 {
			name := 'air.${family}.${sign}.v${count}i32'; parsed, n, bits := vector_float_intrinsic_name(name)!
			assert parsed == id && n == count && bits == 32 && scalar_intrinsic_arity(id) == 2
			key := air_vector_intrinsic_key(id, count, bits)!
			assert key == 61876 + operation * 16 + count - 1 && !seen[key - 61876]; seen[key - 61876] = true
			assert vector_float_intrinsic_key(id, count, bits)! < 61604
			if _ := scalar_intrinsic_name(name) { assert false }
			if _, _, _ := air_vector_float_name(name) { assert false }
			if _ := air_vector_float_key(id, count, bits) { assert false }
		}
		for suffix in ['i32','v0i32','v01i32','v17i32','v999999999999999999i32','v2i1','v2i16','v2i31','v2i33','v2i64','v2i032','v2i+32','v2f32','v2i32.spoof','nxv2i32'] {
			if _, _, _ := vector_float_intrinsic_name('air.${family}.${sign}.${suffix}') { assert false }
		}
		for spelling in ['air.${family}.v2i32','air.${family}.x.v2i32','air.${family}.${sign}.u.v2i32','air.fast_${family}.${sign}.v2i32'] { if _, _, _ := vector_float_intrinsic_name(spelling) { assert false } }
		for bits in [u32(0),1,16,31,33,64,65]! { if _ := air_vector_intrinsic_key(id, 2, bits) { assert false } }
		for count in [0,17]! { if _ := air_vector_intrinsic_key(id, count, 32) { assert false } }
	}
	for value in seen { assert value }
	println('AIR-VECTOR-INTEGER-EXTREMA-NAMES: 64 appended signed/unsigned i32 min/max identities, stable previous keys, exact names/signs/arity/width/count and namespace guards PASS')
}

fn test_air_vector_bit_names_and_cache() {
	mut seen := [32]bool{}
	for operation, id in [ScalarIntrinsic.ctpop, .bitreverse]! {
		family := if id == .ctpop { 'popcount' } else { 'reverse_bits' }
		for count in 1 .. 17 {
			name := 'air.${family}.v${count}i32'
			parsed, n, bits := vector_float_intrinsic_name(name)!
			assert parsed == id && n == count && bits == 32 && scalar_intrinsic_arity(id) == 1
			key := air_vector_intrinsic_key(id, count, bits)!
			assert key == 61940 + operation * 16 + count - 1 && !seen[key - 61940]
			seen[key - 61940] = true
			assert vector_float_intrinsic_key(id, count, bits)! < 61604
			if _ := scalar_intrinsic_name(name) { assert false }
			if _, _, _ := air_vector_float_name(name) { assert false }
			if _ := air_vector_float_key(id, count, bits) { assert false }
		}
		for suffix in ['i32','v0i32','v01i32','v17i32','v999999999999999999i32','v2i1','v2i16','v2i31','v2i33','v2i032','v2i+32','v2f32','v2i32.spoof','nxv2i32'] {
			if _, _, _ := vector_float_intrinsic_name('air.${family}.${suffix}') { assert false }
		}
		for prefix in ['s.','u.','fast_'] {
			if _, _, _ := vector_float_intrinsic_name('air.${prefix}${family}.v2i32') { assert false }
		}
		for bits in [u32(0),1,16,31,33,65]! { if _ := air_vector_intrinsic_key(id, 2, bits) { assert false } }
		for count in [0,17]! { if _ := air_vector_intrinsic_key(id, count, 32) { assert false } }
	}
	for value in seen { assert value }
	if _ := air_vector_integer_key(.bswap, 2, 32) { assert false }
	println('AIR-VECTOR-BIT-NAMES: 32 appended i32 popcount/reverse_bits identities, stable previous keys, unary signatures, exact names/widths/counts and namespace guards PASS')
}

fn test_air_vector_zero_count_names_and_cache() {
	mut seen := [32]bool{}
	for operation, id in [ScalarIntrinsic.ctlz, .cttz]! {
		family := if id == .ctlz { 'clz' } else { 'ctz' }
		for count in 1 .. 17 {
			name := 'air.${family}.v${count}i32'
			parsed, n, bits := vector_float_intrinsic_name(name)!
			assert parsed == id && n == count && bits == 32 && scalar_intrinsic_arity(id) == 2
			key := air_vector_intrinsic_key(id, count, bits)!
			assert key == 61972 + operation * 16 + count - 1 && !seen[key - 61972]
			seen[key - 61972] = true
			assert vector_float_intrinsic_key(id, count, bits)! < 61604
			if _ := scalar_intrinsic_name(name) { assert false }
			if _, _, _ := air_vector_float_name(name) { assert false }
			if _ := air_vector_float_key(id, count, bits) { assert false }
		}
		for suffix in ['i32','v0i32','v01i32','v17i32','v999999999999999999i32','v2i1','v2i16','v2i31','v2i33','v2i64','v2i032','v2i+32','v2f32','v2i32.spoof','nxv2i32','s.v2i32','u.v2i32'] {
			if _, _, _ := vector_float_intrinsic_name('air.${family}.${suffix}') { assert false }
		}
		for bits in [u32(0),1,16,31,33,64,65]! { if _ := air_vector_intrinsic_key(id, 2, bits) { assert false } }
		for count in [0,17]! { if _ := air_vector_intrinsic_key(id, count, 32) { assert false } }
	}
	for value in seen { assert value }
	println('AIR-VECTOR-ZERO-COUNT-NAMES: 32 appended i32 clz/ctz identities, stable previous keys, binary flag signatures and exact names/widths/counts/namespaces PASS')
}

fn test_air_vector_i64_bit_names_and_cache() {
	mut seen := [32]bool{}
	for operation, id in [ScalarIntrinsic.ctpop, .bitreverse]! {
		family := if id == .ctpop { 'popcount' } else { 'reverse_bits' }
		for count in 1 .. 17 {
			name := 'air.${family}.v${count}i64'
			parsed, n, bits := vector_float_intrinsic_name(name)!
			assert parsed == id && n == count && bits == 64 && scalar_intrinsic_arity(id) == 1
			key := air_vector_intrinsic_key(id, count, bits)!
			assert key == 62004 + operation * 16 + count - 1 && !seen[key - 62004]
			seen[key - 62004] = true
			assert air_vector_intrinsic_key(id, count, 32)! == 61940 + operation * 16 + count - 1
			assert vector_float_intrinsic_key(id, count, bits)! < 61604
			if _ := scalar_intrinsic_name(name) { assert false }
			if _, _, _ := air_vector_float_name(name) { assert false }
			if _ := air_vector_float_key(id, count, bits) { assert false }
		}
		for suffix in ['i64','v0i64','v01i64','v17i64','v999999999999999999i64','v2i1','v2i16','v2i63','v2i65','v2i064','v2i+64','v2f64','v2i64.spoof','nxv2i64','s.v2i64','u.v2i64'] {
			if _, _, _ := vector_float_intrinsic_name('air.${family}.${suffix}') { assert false }
		}
		for bits in [u32(0),1,16,31,33,63,65]! { if _ := air_vector_intrinsic_key(id, 2, bits) { assert false } }
		for count in [0,17]! { if _ := air_vector_intrinsic_key(id, count, 64) { assert false } }
	}
	for value in seen { assert value }
	for id in [ScalarIntrinsic.smulh, .umulh, .sadd_sat, .ssub_sat, .uadd_sat, .usub_sat, .smin, .smax, .umin, .umax, .ctlz, .cttz, .bswap]! {
		if _ := air_vector_intrinsic_key(id, 2, 64) { assert false }
	}
	println('AIR-VECTOR-I64-BIT-NAMES: 32 appended i64 popcount/reverse_bits identities, stable i32/LLVM keys, exact widths/counts/namespaces and other-family i64 refusals PASS')
}
