// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_vector_ldexp_identity_states_and_names() {
	mut values := 0
	for bits in [u32(16), 32]! {
		mask := constant_mask(bits); sign := u64(1) << (bits - 1); inf := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }; nan := if bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) }
		for sample in 0 .. 65536 {
			mut input := ScalarVectorValue{}; mut exponents := ScalarVectorValue{}
			for lane in 0 .. 16 { x := if bits == 16 { u64((sample + lane) % 65536) } else { u64(u32(sample + lane) * u32(0x9e3779b9)) }; input.lanes[lane] = IntegerValue{value: x | ~mask}; exponents.lanes[lane] = IntegerValue{value: ~u64(0xffffffff)} }
			result := ldexp_intrinsic_vector(input, exponents, bits, 16)!
			for lane in 0 .. 16 { x := input.lanes[lane].value & mask; assert result.lanes[lane] == IntegerValue{value: if x & (sign - 1) > inf { nan } else { x }}; values++ }
		}
	}
	assert values == 2097152
	mut checks := 0; mut seen := [32]bool{}
	for bits in [u32(16), 32]! { for count in 1 .. 17 {
		id, n, width := vector_float_intrinsic_name('llvm.ldexp.v${count}f${bits}.v${count}i32')!; assert id == .ldexp && n == count && width == bits
		key := vector_float_intrinsic_key(id, count, bits)!; assert key >= 576 && key < 608 && !seen[key - 576]; seen[key - 576] = true
		for target in 0 .. count { for side in 0 .. 2 {
			mut sources := [2]ScalarVectorValue{}; sources[side].lanes[target] = IntegerValue{poison: true}; result := ldexp_intrinsic_vector(sources[0], sources[1], bits, count)!
			for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); checks++ }; assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
			sources[side].undef = u16(1) << u32(target); if _ := ldexp_intrinsic_vector(sources[0], sources[1], bits, count) { assert false, 'undef dominates poison' }; checks++
		} }
	} }; for slot in seen { assert slot }; assert checks == 6528
	for name in ['llvm.ldexp.f32.i32', 'llvm.ldexp.v0f16.v0i32', 'llvm.ldexp.v01f16.v1i32', 'llvm.ldexp.v17f32.v17i32', 'llvm.ldexp.v999999999999999f16.v1i32', 'llvm.ldexp.v2f64.v2i32', 'llvm.ldexp.v2bf16.v2i32', 'llvm.ldexp.v2f32.v2i64', 'llvm.ldexp.v2f32.i32', 'llvm.ldexp.v2f32.v1i32', 'llvm.ldexp.v2f32.v02i32', 'llvm.ldexp.v2f32.v999999999999999i32', 'llvm.ldexp.v2f32.v2f32', 'llvm.ldexp.v2f32.v2i032', 'llvm.ldexp.v2f32.v2i32.spoof', 'llvm.ldexp.nxv2f32.nxv2i32', 'llvm.ldexp.v2f32', 'air.ldexp.v2f32.v2i32'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false, name } }
	for width in [u32(0), 1, 64]! { if _ := ldexp_intrinsic_vector(ScalarVectorValue{}, ScalarVectorValue{}, width, 1) { assert false, 'width' } }; for count in [0, 17] { if _ := ldexp_intrinsic_vector(ScalarVectorValue{}, ScalarVectorValue{}, 16, count) { assert false, 'count' } }
	for side in 0 .. 2 { for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut sources := [2]ScalarVectorValue{}; sources[side].lanes[0] = tag; if _ := ldexp_intrinsic_vector(sources[0], sources[1], 32, 1) { assert false, 'scalar lane tag' } } }
	println('AIR-VECTOR-LDEXP-STATES: ${values} exact zero-exponent identity lane results, ${checks} two-source poison/undef/freeze checks and 32 canonical overload/cache identities plus name/shape/tag guards PASS')
}
