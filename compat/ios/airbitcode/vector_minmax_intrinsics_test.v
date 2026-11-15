// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Transform finite encodings to monotonically ordered unsigned keys. This
// independent oracle also orders -0 below +0 without host floating arithmetic.
fn vector_minmax_reference(id ScalarIntrinsic, bits u32, a u64, b u64) u64 {
	mask := constant_mask(bits); sign := u64(1) << (bits - 1); x := a & mask; y := b & mask
	inf := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }
	if id in [.minimumnum, .maximumnum, .minnum, .maxnum]! {
		if x & (sign - 1) > inf && y & (sign - 1) <= inf { return y }
		if y & (sign - 1) > inf && x & (sign - 1) <= inf { return x }
	}
	if x & (sign - 1) > inf || y & (sign - 1) > inf { return if bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) } }
	x_key := if x & sign != 0 { ~x & mask } else { x | sign }; y_key := if y & sign != 0 { ~y & mask } else { y | sign }
	return if (x_key < y_key) == (id in [.minimum, .minimumnum, .minnum]!) { x } else { y }
}
fn test_vector_minmax_encodings_and_pairs() {
	mut checks := 0
	for bits in [u32(16), 32]! { for sample in 0 .. 65536 {
		mut left := ScalarVectorValue{}; mut right := ScalarVectorValue{}
		for lane in 0 .. 16 {
			left.lanes[lane] = IntegerValue{value: (if bits == 16 { u64((sample + lane) % 65536) } else { u64(u32(sample) * u32(0x9e3779b9) + u32(lane) * u32(0x01010101)) }) | ~constant_mask(bits)}
			right.lanes[lane] = IntegerValue{value: (u64(sample) * u64(0x9e3779b97f4a7c15) + u64(lane) * u64(0x01010101)) | ~constant_mask(bits)}
		}
		a := left; b := right
		for id in [ScalarIntrinsic.minimum, .maximum, .minimumnum, .maximumnum, .minnum, .maxnum]! { result := minmax_intrinsic_vector(id, left, right, bits, 16)!; for lane in 0 .. 16 { assert result.lanes[lane] == IntegerValue{value: vector_minmax_reference(id, bits, left.lanes[lane].value, right.lanes[lane].value)}; checks++ }; assert result.undef == 0 && left == a && right == b }
	} }
	assert checks == 12582912
	mut pairs := 0
	for bits in [u32(16), 32]! {
		words := if bits == 16 { [u64(0), 0x8000, 1, 0x8001, 0x3ff, 0x83ff, 0x400, 0x8400, 0x3c00, 0xbc00, 0x7c00, 0xfc00, 0x7c01, 0xfc01, 0x7e55, 0xfe55]! } else { [u64(0), 0x80000000, 1, 0x80000001, 0x7fffff, 0x807fffff, 0x800000, 0x80800000, 0x3f800000, 0xbf800000, 0x7f800000, 0xff800000, 0x7f800001, 0xff800001, 0x7fc12345, 0xffc12345]! }
		for x in words { for y in words { for id in [ScalarIntrinsic.minimum, .maximum, .minimumnum, .maximumnum, .minnum, .maxnum]! { mut a := ScalarVectorValue{}; mut b := ScalarVectorValue{}; a.lanes[0] = IntegerValue{value: x}; b.lanes[0] = IntegerValue{value: y}; r := minmax_intrinsic_vector(id, a, b, bits, 1)!; assert r.lanes[0].value == vector_minmax_reference(id, bits, x, y); assert r == minmax_intrinsic_vector(id, b, a, bits, 1)!; pairs++ } } }
	}
	assert pairs == 3072
	println('AIR-VECTOR-MINMAX-VALUES: ${checks} ordered-key checks across all half encodings and deterministic float patterns plus ${pairs} edge pairs, NaN propagation and number preference, signed zeros, masking, commutativity and snapshots PASS')
}
fn test_vector_minmax_lane_states_and_names() {
	mut checks := 0; mut seen := [192]bool{}
	for bits in [u32(16), 32]! { for id in [ScalarIntrinsic.minimum, .maximum, .minimumnum, .maximumnum, .minnum, .maxnum]! { for count in 1 .. 17 {
		parsed, n, parsed_bits := vector_float_intrinsic_name('llvm.${id}.v${count}f${bits}')!; assert parsed == id && n == count && parsed_bits == bits
		key := vector_float_intrinsic_key(id, count, bits)!; assert key >= 320 && key < 512 && !seen[key - 320]; seen[key - 320] = true
		for target in 0 .. count { for side in 0 .. 2 {
			mut a := ScalarVectorValue{}; mut b := ScalarVectorValue{}
			if side == 0 { a.lanes[target] = IntegerValue{poison: true} } else { b.lanes[target] = IntegerValue{poison: true} }
			r := minmax_intrinsic_vector(id, a, b, bits, count)!; for lane in 0 .. count { assert r.lanes[lane].poison == (lane == target); checks++ }; assert frozen_vector(r, count)!.lanes[target] == IntegerValue{}
			if side == 0 { a.undef = u16(1) << u32(target) } else { b.undef = u16(1) << u32(target) }; if _ := minmax_intrinsic_vector(id, a, b, bits, count) { assert false, 'undef' }; checks++
		} }
	} } }; for slot in seen { assert slot }
	for name in ['llvm.minimum.f32', 'llvm.minimum.v0f16', 'llvm.minimum.v01f16', 'llvm.maximum.v17f32', 'llvm.maximum.v999999999999999999f16', 'llvm.minimum.v2f64', 'llvm.maximum.v2bf16', 'llvm.minimum.v2i32', 'llvm.minimum.v2f016', 'llvm.maximum.v2f32.spoof', 'llvm.minimum.nxv2f32', 'llvm.minimum_num.v2f32', 'llvm.maximumnum.v2f64'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false, name } }
	for id in [ScalarIntrinsic.fabs, .sqrt, .floor, .fma, .ldexp]! { if _ := minmax_intrinsic_vector(id, ScalarVectorValue{}, ScalarVectorValue{}, 32, 1) { assert false, 'family' } }
	for width in [u32(0), 1, 64]! { if _ := minmax_intrinsic_vector(.minimum, ScalarVectorValue{}, ScalarVectorValue{}, width, 1) { assert false, 'width' } }; for count in [0, 17] { if _ := minmax_intrinsic_vector(.maximum, ScalarVectorValue{}, ScalarVectorValue{}, 16, count) { assert false, 'count' } }
	for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := minmax_intrinsic_vector(.minimum, source, ScalarVectorValue{}, 32, 1) { assert false, 'left tag' }; if _ := minmax_intrinsic_vector(.maximum, ScalarVectorValue{}, source, 32, 1) { assert false, 'right tag' } }
	assert checks == 39168
	println('AIR-VECTOR-MINMAX-STATES: ${checks} two-source poison/undef/freeze checks, all 192 min/max overload/cache identities and name/shape/family/tag guards PASS')
}
