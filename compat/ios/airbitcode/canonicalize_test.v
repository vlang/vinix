// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn canonical_encoding_reference(bits u32, word u64) u64 {
	shift := if bits == 16 { u32(10) } else { u32(23) }
	exponent := if bits == 16 { u64(31) } else { u64(255) }
	value := word & constant_mask(bits)
	return if (value >> shift) & exponent == exponent && value & ((u64(1) << shift) - 1) != 0 { value | (u64(1) << (shift - 1)) } else { value }
}
fn test_canonicalize_encodings_snapshots_and_states() {
	mut checks := 0
	for bits in [u32(16), 32]! {
		for sample in u32(0) .. 65536 {
			mut source := ScalarVectorValue{}
			for lane in 0 .. 16 {
				word := if bits == 16 { u64(u16(sample + u32(lane))) } else { u64(sample * u32(0x9e3779b9) + u32(lane) * u32(0x1f123bb5)) }
				source.lanes[lane] = IntegerValue{value: word | ~constant_mask(bits)}
			}
			before := source; result := canonical_float_vector(source, bits, 16)!
			for lane in 0 .. 16 {
				expected := canonical_encoding_reference(bits, source.lanes[lane].value)
				assert result.lanes[lane] == IntegerValue{value: expected}
				assert scalar_intrinsic_value(.canonicalize, bits, source.lanes[lane].value, 0)! == expected
				assert canonical_float(bits, expected) == expected
				checks++
			}
			assert source == before
		}
	}
	assert checks == 2097152
	mut states := 0
	for bits in [u32(16), 32]! { for count in 1 .. 17 { for target in 0 .. count {
		mut source := ScalarVectorValue{}; source.lanes[target] = IntegerValue{poison: true}
		result := canonical_float_vector(source, bits, count)!
		for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); states++ }
		assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
		source.undef = u16(1) << u32(target); if _ := canonical_float_vector(source, bits, count) { assert false, 'strict undef' }; states++
	} } }
	assert states == 3264
	println('AIR-CANONICALIZE-UNIT: ${checks} exact lane/scalar/idempotence checks, exhaustive half, deterministic float, snapshots and ${states} poison/undef/freeze states PASS')
}
fn test_canonicalize_names_keys_and_guards() {
	assert scalar_canonicalize_cache_base == 2024 && scalar_intrinsic_cache_slots == 2179
	assert vector_canonicalize_cache_base == 34752 && vector_float_intrinsic_slots == 61972
	for bits in [u32(16), 32]! {
		assert scalar_intrinsic_name('llvm.canonicalize.f${bits}')! == .canonicalize
		assert scalar_intrinsic_arity(.canonicalize) == 1 && !scalar_integer_intrinsic(.canonicalize)
		for count in 1 .. 17 {
			id, n, width := vector_float_intrinsic_name('llvm.canonicalize.v${count}f${bits}')!
			assert id == .canonicalize && n == count && width == bits
			assert vector_float_intrinsic_key(id, count, bits)! == 34752 + int(bits == 16) * 16 + count - 1
		}
	}
	for name in ['llvm.canonicalize.f64', 'llvm.canonicalize.bf16', 'llvm.canonicalize.f032', 'llvm.canonicalize.f32.spoof', 'air.canonicalize.f32'] { if _ := scalar_intrinsic_name(name) { assert false, name } }
	for name in ['llvm.canonicalize.v0f32', 'llvm.canonicalize.v17f32', 'llvm.canonicalize.v01f32', 'llvm.canonicalize.v99999999999999999999f16', 'llvm.canonicalize.v2f64', 'llvm.canonicalize.nxv2f32', 'llvm.canonicalize.v2i32', 'llvm.canonicalize.v2bf16', 'llvm.canonicalize.v2f32.spoof'] { if _, _, _ := vector_float_intrinsic_name(name) { assert false, name } }
	for width in [u32(0), 1, 64]! { if _ := scalar_intrinsic_value(.canonicalize, width, 0, 0) { assert false }; if _ := canonical_float_vector(ScalarVectorValue{}, width, 1) { assert false } }
	for count in [0, 17] { if _ := canonical_float_vector(ScalarVectorValue{}, 16, count) { assert false } }
	for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := canonical_float_vector(source, 32, 1) { assert false } }
	println('AIR-CANONICALIZE-NAMES: 34 appended identities; canonical names, integer classification, widths, shapes and scalar tags PASS')
}
