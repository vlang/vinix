// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_vector_sign_intrinsics_all_half_and_float_patterns() {
	mut checks := 0
	for bits in [u32(16), 32]! { for sample in 0 .. 65536 {
		mut left := ScalarVectorValue{}; mut right := ScalarVectorValue{}
		for lane in 0 .. 16 {
			left.lanes[lane] = IntegerValue{value: (if bits == 16 { u64((sample + lane) % 65536) } else { u64(u32(sample) * u32(0x9e3779b9) + u32(lane) * u32(0x01010101)) }) | ~constant_mask(bits)}
			right.lanes[lane] = IntegerValue{value: (u64(sample) * u64(0x9e3779b97f4a7c15) + u64(lane) * u64(0x01010101)) | ~constant_mask(bits)}
		}
		before_left := left; before_right := right; sign := u64(1) << (bits - 1)
		for id in [ScalarIntrinsic.fabs, .copysign]! {
			result := sign_intrinsic_vector(id, left, right, bits, 16)!
			for lane in 0 .. 16 { expected := (left.lanes[lane].value & (sign - 1)) | if id == .copysign { right.lanes[lane].value & sign } else { u64(0) }; assert result.lanes[lane] == IntegerValue{value: expected}; checks++ }
			assert result.undef == 0 && left == before_left && right == before_right
		}
	} }
	assert checks == 4194304
	println('AIR-VECTOR-SIGN-VALUES: ${checks} exact raw-bit checks, all half encodings and deterministic float patterns, NaN payloads/signaling bits, source masking and snapshots PASS')
}
fn test_vector_sign_intrinsic_lane_states_and_names() {
	mut checks := 0; mut seen := [vector_sign_intrinsic_slots]bool{}
	for bits in [u32(16), 32]! { for id in [ScalarIntrinsic.fabs, .copysign]! { for count in 1 .. 17 {
		name := 'llvm.${if id == .fabs { 'fabs' } else { 'copysign' }}.v${count}f${bits}'
		parsed, lanes, width := vector_sign_intrinsic_name(name)!; assert parsed == id && lanes == count && width == bits
		key := vector_sign_intrinsic_key(id, count, bits)!; assert !seen[key]; seen[key] = true
		for target in 0 .. count {
			mut left := ScalarVectorValue{}; mut right := ScalarVectorValue{}
			left.lanes[target] = IntegerValue{poison: true}; a := sign_intrinsic_vector(id, left, right, bits, count)!
			for lane in 0 .. count { assert a.lanes[lane].poison == (lane == target); checks++ }
			assert frozen_vector(a, count)!.lanes[target] == IntegerValue{}
			left = ScalarVectorValue{}; right.lanes[target] = IntegerValue{poison: true}; b := sign_intrinsic_vector(id, left, right, bits, count)!
			for lane in 0 .. count { assert b.lanes[lane].poison == (id == .copysign && lane == target); checks++ }
			left.undef = u16(1) << u32(target); if _ := sign_intrinsic_vector(id, left, right, bits, count) { assert false, 'left undef' }; checks++
			left = ScalarVectorValue{}; right.undef = u16(1) << u32(target)
			if id == .copysign { if _ := sign_intrinsic_vector(id, left, right, bits, count) { assert false, 'right undef' } } else { assert sign_intrinsic_vector(id, left, right, bits, count)!.undef == 0 }; checks++
		}
	} } }
	for entry in seen { assert entry }
	for name in ['llvm.fabs.f32', 'llvm.fabs.v0f16', 'llvm.fabs.v01f16', 'llvm.fabs.v17f32', 'llvm.fabs.v999999999999999999999999f16', 'llvm.fabs.v2f64', 'llvm.fabs.v2i32', 'llvm.fabs.v2f016', 'llvm.fabs.v2f32.spoof', 'llvm.fabs.vf16', 'llvm.fabs.nxv2f32', 'llvm.sqrt.v2f32', 'air.fabs.v2f32', 'llvm.copysign.v2f32x'] { if _, _, _ := vector_sign_intrinsic_name(name) { assert false, 'unsupported name: ' + name } }
	for id in [ScalarIntrinsic.sqrt, .floor, .fma]! { if _ := sign_intrinsic_vector(id, ScalarVectorValue{}, ScalarVectorValue{}, 32, 1) { assert false, 'operation family' } }
	for bits in [u32(0), 1, 64]! { if _ := sign_intrinsic_vector(.fabs, ScalarVectorValue{}, ScalarVectorValue{}, bits, 1) { assert false, 'width' } }
	for count in [0, 17] { if _ := sign_intrinsic_vector(.fabs, ScalarVectorValue{}, ScalarVectorValue{}, 16, count) { assert false, 'count' } }
	for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := sign_intrinsic_vector(.fabs, source, ScalarVectorValue{}, 32, 1) { assert false, 'left scalar tag' }; if _ := sign_intrinsic_vector(.copysign, ScalarVectorValue{}, source, 32, 1) { assert false, 'right scalar tag' } }
	assert checks == 13056
	println('AIR-VECTOR-SIGN-STATES: ${checks} localized poison/strict undef/freeze checks, all 64 canonical overload/cache identities and name/shape/tag guards PASS')
}
