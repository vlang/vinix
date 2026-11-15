// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Exact binary16 value in units of 2^-24; the largest value fits in 40 bits.
fn sqrt_half_units(raw u64) u64 { e := int(raw >> 10); return if e == 0 { raw } else { (1024 + (raw & 1023)) << u32(e - 1) } }
fn test_vector_sqrt_all_half_encodings() {
	mut checks := 0
	for sample in 0 .. 65536 {
		mut source := ScalarVectorValue{}
		for lane in 0 .. 16 { source.lanes[lane] = IntegerValue{value: u64((sample + lane) % 65536) | ~u64(0xffff)} }
		before := source; result := sqrt_intrinsic_vector(source, 16, 16)!
		for lane in 0 .. 16 {
			x := u64((sample + lane) % 65536); y := result.lanes[lane]; assert !y.poison && !y.aggregate && !y.vector
			if x & 0x7fff == 0 { assert y.value == x }
			else if x > 0x7c00 { assert y.value == 0x7e00 }
			else if x == 0x7c00 { assert y.value == x }
			else {
				assert y.value >= 0x0c00 && y.value <= 0x5bff
				center := sqrt_half_units(y.value); lower := (sqrt_half_units(y.value - 1) + center) / 2; upper := (sqrt_half_units(y.value + 1) + center) / 2
				// Input * 2^48 and squared midpoints fit u64 even at max half.
				target := sqrt_half_units(x) << 24; even := y.value & 1 == 0
				assert target > lower * lower || (target == lower * lower && even)
				assert target < upper * upper || (target == upper * upper && even)
			}
			checks++
		}
		assert source == before && result.undef == 0
	}
	assert checks == 1048576
	println('AIR-VECTOR-SQRT-HALF: ${checks} exact squared-midpoint checks for every half encoding and all 16 lanes, signed zeros, preferred NaNs, masking and snapshots PASS')
}
fn test_vector_sqrt_float_patterns_states_and_names() {
	inputs := [u64(0), 0x80000000, 0x3f800000, 0x40800000, 0x41100000, 0x40a00000, 0x40000000, 1, 0x800000, 0x7f7fffff, 0xbf800000, 0x80000001, 0x7f800000, 0xff800000, 0xff800001, 0x7fc12345]!
	expected := [u64(0), 0x80000000, 0x3f800000, 0x40000000, 0x40400000, 0x400f1bbd, 0x3fb504f3, 0x1a3504f3, 0x20000000, 0x5f7fffff, 0x7fc00000, 0x7fc00000, 0x7f800000, 0x7fc00000, 0x7fc00000, 0x7fc00000]!
	mut source := ScalarVectorValue{}; for lane in 0 .. 16 { source.lanes[lane] = IntegerValue{value: inputs[lane] | ~u64(0xffffffff)} }
	result := sqrt_intrinsic_vector(source, 32, 16)!; for lane in 0 .. 16 { assert result.lanes[lane] == IntegerValue{value: expected[lane]} }
	mut checks := 0; mut seen := [32]bool{}
	for bits in [u32(16), 32]! { for count in 1 .. 17 {
		id, n, b := vector_float_intrinsic_name('llvm.sqrt.v${count}f${bits}')!; assert id == .sqrt && n == count && b == bits
		key := vector_float_intrinsic_key(id, count, bits)!; assert key >= 288 && key < 320 && !seen[key - 288]; seen[key - 288] = true
		for target in 0 .. count {
			mut input := ScalarVectorValue{}; input.lanes[target] = IntegerValue{poison: true}; output := sqrt_intrinsic_vector(input, bits, count)!
			for lane in 0 .. count { assert output.lanes[lane].poison == (lane == target); checks++ }; assert frozen_vector(output, count)!.lanes[target] == IntegerValue{}
			input.undef = u16(1) << u32(target); if _ := sqrt_intrinsic_vector(input, bits, count) { assert false, 'undef' }; checks++
		}
	} }; for slot in seen { assert slot }
	for name in ['llvm.sqrt.f16', 'llvm.sqrt.v0f32', 'llvm.sqrt.v01f16', 'llvm.sqrt.v17f32', 'llvm.sqrt.v999999999999999999f16', 'llvm.sqrt.v2f64', 'llvm.sqrt.v2bf16', 'llvm.sqrt.v2i16', 'llvm.sqrt.v2f016', 'llvm.sqrt.v2f32.spoof', 'llvm.sqrt.nxv2f32', 'air.sqrt.v2f32'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false, name } }
	for width in [u32(0), 1, 64]! { if _ := sqrt_intrinsic_vector(ScalarVectorValue{}, width, 1) { assert false, 'width' } }; for count in [0, 17] { if _ := sqrt_intrinsic_vector(ScalarVectorValue{}, 16, count) { assert false, 'count' } }
	for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut input := ScalarVectorValue{}; input.lanes[0] = tag; if _ := sqrt_intrinsic_vector(input, 32, 1) { assert false, 'lane tag' } }
	for offset in [-1, 999] { if _, _ := vector_float_overload('llvm.sqrt.v2f16', offset) { assert false, 'offset' } }
	assert checks == 3264
	println('AIR-VECTOR-SQRT-STATES: 16 float edge patterns, ${checks} lane poison/undef/freeze checks, all 32 new cache identities and shape/name/tag guards PASS')
}
