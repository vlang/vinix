// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_vector_fma_encodings_and_states() {
	mut identities := 0
	for bits in [u32(16), 32]! {
		mask := constant_mask(bits); sign := u64(1) << (bits - 1)
		inf := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }; nan := if bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) }; one := if bits == 16 { u64(0x3c00) } else { u64(0x3f800000) }
		for sample in 0 .. 65536 {
			mut a := ScalarVectorValue{}; mut b := ScalarVectorValue{}; mut c := ScalarVectorValue{}
			for lane in 0 .. 16 { x := if bits == 16 { u64((sample + lane) % 65536) } else { u64(u32(sample + lane) * u32(0x9e3779b9)) }; a.lanes[lane] = IntegerValue{value: x | ~mask}; b.lanes[lane] = IntegerValue{value: one | ~mask}; c.lanes[lane] = IntegerValue{value: (x & sign) | ~mask} }
			result := fma_intrinsic_vector(a, b, c, bits, 16)!
			for lane in 0 .. 16 { x := a.lanes[lane].value & mask; assert result.lanes[lane] == IntegerValue{value: if x & (sign - 1) > inf { nan } else { x }}; identities++ }
		}
	}
	assert identities == 2097152
	mut checks := 0; mut seen := [32]bool{}
	for bits in [u32(16), 32]! { for count in 1 .. 17 {
		id, n, width := vector_float_intrinsic_name('llvm.fma.v${count}f${bits}')!; assert id == .fma && n == count && width == bits
		key := vector_float_intrinsic_key(id, count, bits)!; assert key >= 512 && key < 544 && !seen[key - 512]; seen[key - 512] = true
		for target in 0 .. count { for side in 0 .. 3 {
			mut sources := [3]ScalarVectorValue{}; sources[side].lanes[target] = IntegerValue{poison: true}
			result := fma_intrinsic_vector(sources[0], sources[1], sources[2], bits, count)!
			for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); checks++ }; assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
			sources[side].undef = u16(1) << u32(target); if _ := fma_intrinsic_vector(sources[0], sources[1], sources[2], bits, count) { assert false, 'undef must dominate poison' }; checks++
		} }
	} }; for slot in seen { assert slot }; assert checks == 9792
	for name in ['llvm.fma.f32', 'llvm.fma.v0f16', 'llvm.fma.v01f16', 'llvm.fma.v17f32', 'llvm.fma.v999999999999999999f16', 'llvm.fma.v2f64', 'llvm.fma.v2bf16', 'llvm.fma.v2i32', 'llvm.fma.v2f016', 'llvm.fma.v2f32.spoof', 'llvm.fma.nxv2f32', 'llvm.fmuladd.v2f32', 'air.fma.v2f32'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false, name } }
	for width in [u32(0), 1, 64]! { if _ := fma_intrinsic_vector(ScalarVectorValue{}, ScalarVectorValue{}, ScalarVectorValue{}, width, 1) { assert false, 'width' } }; for count in [0, 17] { if _ := fma_intrinsic_vector(ScalarVectorValue{}, ScalarVectorValue{}, ScalarVectorValue{}, 16, count) { assert false, 'count' } }
	for side in 0 .. 3 { for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut sources := [3]ScalarVectorValue{}; sources[side].lanes[0] = tag; if _ := fma_intrinsic_vector(sources[0], sources[1], sources[2], 32, 1) { assert false, 'scalar lane tag' } } }
	println('AIR-VECTOR-FMA-STATES: ${identities} exact a*1+signed-zero identity lane results, ${checks} three-source poison/undef/freeze checks and 32 canonical cache/name/shape/tag guards PASS')
}
