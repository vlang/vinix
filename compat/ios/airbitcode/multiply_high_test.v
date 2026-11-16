// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Independent schoolbook bit multiplication of magnitudes, followed by a
// full 2N-bit two's-complement negation for a negative product.
fn multiply_high_reference(bits u32, signed bool, a u64, b u64) u64 {
	mask := constant_mask(bits); sign := u64(1) << (bits - 1)
	x := a & mask; y := b & mask
	nx := signed && x & sign != 0; ny := signed && y & sign != 0
	mx := if nx { (u64(0) - x) & mask } else { x }
	my := if ny { (u64(0) - y) & mask } else { y }
	mut columns := [128]u32{}
	for i in u32(0) .. bits { if mx & (u64(1) << i) != 0 { for j in u32(0) .. bits { columns[i + j] += u32((my >> j) & 1) } } }
	mut carry := u32(0)
	for i in u32(0) .. bits * 2 { sum := columns[i] + carry; columns[i] = sum & 1; carry = sum >> 1 }
	if nx != ny {
		carry = 1
		for i in u32(0) .. bits * 2 { sum := (columns[i] ^ 1) + carry; columns[i] = sum & 1; carry = sum >> 1 }
	}
	mut result := u64(0)
	for i in u32(0) .. bits { result |= u64(columns[bits + i]) << i }
	return result
}
fn test_multiply_high_all_small_values_and_wide_patterns() {
	mut checks := 0
	for bits in u32(1) .. 9 { for a in u64(0) .. u64(1) << bits { for b in u64(0) .. u64(1) << bits { for id in [ScalarIntrinsic.smulh, .umulh]! {
		assert scalar_integer_mulh_value(id, bits, a, b)! == multiply_high_reference(bits, id == .smulh, a, b); checks++
	} } } }
	for bits in u32(1) .. 65 { for sample in u64(0) .. 512 { for id in [ScalarIntrinsic.smulh, .umulh]! {
		mask := constant_mask(bits); sign := u64(1) << (bits - 1)
		a := [u64(0), 1, mask, sign, sign - 1, sign + 1, sample * u64(0x9e3779b97f4a7c15), sample * u64(0x1f123bb59e3779b9)]![sample % 8]
		b := [mask, sign, sign - 1, 1, u64(0), sample * u64(0xd1b54a32d192ed03), sign + 1, sample * u64(0x94d049bb133111eb)]![sample % 8]
		expected := multiply_high_reference(bits, id == .smulh, a, b)
		assert scalar_integer_mulh_value(id, bits, a | ~mask, b | ~mask)! == expected
		assert scalar_intrinsic_value(id, bits, a, b)! == expected
		assert scalar_integer_mulh_value(id, bits, b, a)! == expected; checks++
	} } }
	assert checks == 240296
	println('AIR-MULH-UNIT: ${checks} independent bit-column products, exhaustive i1-i8 pairs, i1-i64 boundaries/deterministic samples, upper-bit masking, symmetry and scalar dispatch PASS')
}
fn test_multiply_high_vectors_names_and_cache() {
	mut seen := [vector_float_intrinsic_slots]bool{}
	mut checks := 0; mut states := 0
	assert scalar_mulh_cache_base == 2026 && scalar_intrinsic_cache_slots == 2160
	assert vector_mulh_cache_base == 34784 && vector_float_intrinsic_slots == 61604
	for id in [ScalarIntrinsic.smulh, .umulh]! { for bits in u32(1) .. 65 {
		assert scalar_intrinsic_name('llvm.${id}.i${bits}')! == id && scalar_integer_intrinsic(id) && scalar_intrinsic_arity(id) == 2
		for count in 1 .. 17 {
			parsed, n, width := vector_float_intrinsic_name('llvm.${id}.v${count}i${bits}')!; assert parsed == id && n == count && width == bits
			key := vector_float_intrinsic_key(id, count, bits)!; assert key >= 34784 && key < 36832 && !seen[key]; seen[key] = true
			mut left := ScalarVectorValue{}; mut right := ScalarVectorValue{}
			for lane in 0 .. count { left.lanes[lane] = IntegerValue{value: u64(lane + 1) * u64(0x9e3779b97f4a7c15)}; right.lanes[lane] = IntegerValue{value: ~u64(lane)} }
			a := left; b := right; result := multiply_high_vector(id, left, right, bits, count)!
			for lane in 0 .. count { assert result.lanes[lane].value == multiply_high_reference(bits, id == .smulh, left.lanes[lane].value, right.lanes[lane].value); checks++ }; assert left == a && right == b
			for side in [0, 1] {
				mut x := left; mut y := right
				if side == 0 { x.lanes[count - 1] = IntegerValue{poison: true} } else { y.lanes[count - 1] = IntegerValue{poison: true} }
				r := multiply_high_vector(id, x, y, bits, count)!; assert r.lanes[count - 1].poison && frozen_vector(r, count)!.lanes[count - 1] == IntegerValue{}; states++
				if side == 0 { x.undef |= u16(1) << u32(count - 1) } else { y.undef |= u16(1) << u32(count - 1) }
				if _ := multiply_high_vector(id, x, y, bits, count) { assert false, 'undef must be observed even with poison' }; states++
			}
		}
	} }
	for key in 34784 .. 36832 { assert seen[key] }
	for name in ['llvm.smulh.i0', 'llvm.umulh.i65', 'llvm.smulh.i01', 'llvm.umulh.i32.spoof', 'llvm.smulh.f32'] { if _ := scalar_intrinsic_name(name) { assert false, name } }
	for name in ['llvm.smulh.v0i32', 'llvm.smulh.v17i32', 'llvm.umulh.v01i32', 'llvm.smulh.nxv2i32', 'llvm.umulh.v2i65', 'llvm.smulh.v2f32', 'llvm.smulh.v2i32.spoof'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false, name } }
	for bits in [u32(0), 65]! { if _ := scalar_integer_mulh_value(.smulh, bits, 0, 0) { assert false } }
	if _ := scalar_integer_mulh_value(.clmul, 32, 0, 0) { assert false }
	if _ := scalar_integer_intrinsic_value(.smulh, 32, 0) { assert false, 'unary evaluator' }
	for count in [0, 17] { if _ := multiply_high_vector(.smulh, ScalarVectorValue{}, ScalarVectorValue{}, 32, count) { assert false } }
	for tag in [IntegerValue{vector: true}, IntegerValue{aggregate: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := multiply_high_vector(.umulh, source, ScalarVectorValue{}, 32, 1) { assert false } }
	assert checks == 17408 && states == 8192
	println('AIR-MULH-VECTORS: ${checks} independent lanes and snapshots, ${states} poison/undef/freeze states, all 2048 new vector identities and family/name/shape/tag guards PASS')
}
