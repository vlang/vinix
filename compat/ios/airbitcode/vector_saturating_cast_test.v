// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn vector_saturation_expected(source u32, dest u32, signed bool, word u64) u64 {
	fraction_bits := if source == 16 { u32(10) } else { u32(23) }
	exponent_bits := if source == 16 { u32(5) } else { u32(8) }
	bias := if source == 16 { 15 } else { 127 }
	fraction := word & ((u64(1) << fraction_bits) - 1)
	exponent := (word >> fraction_bits) & ((u64(1) << exponent_bits) - 1)
	negative := word & (u64(1) << (source - 1)) != 0
	if exponent == (u64(1) << exponent_bits) - 1 && fraction != 0 { return 0 }
	if !signed && negative { return 0 }
	sign := u64(1) << (dest - 1)
	limit := if signed { if negative { sign } else { sign - 1 } } else { constant_mask(dest) }
	mut magnitude := fraction | if exponent != 0 { u64(1) << fraction_bits } else { u64(0) }
	mut power := int(if exponent == 0 { u64(1) } else { exponent }) - bias - int(fraction_bits)
	if exponent == (u64(1) << exponent_bits) - 1 { magnitude = limit } else if power < 0 {
		magnitude = if power <= -64 { u64(0) } else { magnitude >> u32(-power) }
	} else { for power > 0 { if magnitude > limit / 2 { magnitude = limit; break }; magnitude *= 2; power-- } }
	if magnitude > limit { magnitude = limit }
	return if negative { (u64(0) - magnitude) & constant_mask(dest) } else { magnitude }
}

fn test_vector_saturating_cast_all_half_and_float_patterns() {
	mut checks := 0
	for bits in u32(1) .. 65 { for source_bits in [u32(16), 32]! { for id in [ScalarIntrinsic.fptosi_sat, .fptoui_sat]! {
		samples := if source_bits == 16 { 65536 } else { 4096 }
		for base := 0; base < samples; base += 16 {
			mut source := ScalarVectorValue{}
			for lane in 0 .. 16 {
				sample := u32(base + lane)
				word := if source_bits == 16 { u64(sample) } else { u64((sample % 512) << 23 | match sample / 512 { 0 { u32(0) } 1 { u32(1) } 2 { u32(0x7fffff) } 3 { u32(0x400000) } else { (sample * u32(0x1f123bb5)) & 0x7fffff } }) }
				source.lanes[lane] = IntegerValue{value: word | ~constant_mask(source_bits)}
			}
			before := source
			result := saturating_cast_vector(id, source, source_bits, bits, 16)!
			for lane in 0 .. 16 { assert result.lanes[lane] == IntegerValue{value: vector_saturation_expected(source_bits, bits, id == .fptosi_sat, source.lanes[lane].value & constant_mask(source_bits))}; checks++ }
			assert source == before && result.undef == 0
		}
	} } }
	assert checks == 8912896
	println('AIR-VECTOR-SATURATING-CAST: ${checks} independent rational lanes, every half encoding and float sign/exponent/fraction patterns across signed/unsigned i1-i64; padding and snapshots PASS')
}

fn test_vector_saturating_cast_states_names_and_guards() {
	mut checks := 0
	for bits in u32(1) .. 65 { for source_bits in [u32(16), 32]! { for id in [ScalarIntrinsic.fptosi_sat, .fptoui_sat]! { for count in 1 .. 17 { for target in 0 .. count {
		mut source := ScalarVectorValue{}; source.lanes[target] = IntegerValue{poison: true}
		result := saturating_cast_vector(id, source, source_bits, bits, count)!
		for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); checks++ }
		assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
		source.undef = u16(1) << u32(target)
		if _ := saturating_cast_vector(id, source, source_bits, bits, count) { assert false }; checks++
	} } } } }
	for name in ['llvm.fptosi.sat.v0i8.v0f32', 'llvm.fptosi.sat.v01i8.v1f32', 'llvm.fptoui.sat.v17i8.v17f16', 'llvm.fptosi.sat.v1i0.v1f32', 'llvm.fptosi.sat.v1i01.v1f32', 'llvm.fptosi.sat.v1i65.v1f32', 'llvm.fptosi.sat.v1i8.v2f32', 'llvm.fptosi.sat.v2i8.v02f32', 'llvm.fptosi.sat.v1i8.v1f64', 'llvm.fptosi.sat.v1i8.v1bf16', 'llvm.fptosi.sat.v1i8.v1f32.spoof', 'llvm.fptosi.sat.v1i8.v1f032', 'llvm.fptosi.sat.v999999999999i8.v1f32', 'llvm.fptosi.sat.v1i999999999999.v1f32', 'llvm.fptosi.sat.i8.f32', 'llvm.fptosi.sat.nxv1i8.nxv1f32', 'air.fptosi.sat.v1i8.v1f32', 'llvm.fptosi.sat.v1i8', 'llvm.fptosi.sat.v1i8.vf32'] {
		if _, _, _, _ := vector_saturating_cast_name(name) { assert false, name }
		if _, _, _ := vector_float_intrinsic_name(name) { assert false, name }
	}
	for count in [0, 17] { if _ := saturating_cast_vector(.fptosi_sat, ScalarVectorValue{}, 32, 8, count) { assert false } }
	for source in [u32(0), 15, 64]! { if _ := saturating_cast_vector(.fptosi_sat, ScalarVectorValue{}, source, 8, 1) { assert false } }
	for bits in [u32(0), 65]! { if _ := saturating_cast_vector(.fptosi_sat, ScalarVectorValue{}, 32, bits, 1) { assert false } }
	for id in [ScalarIntrinsic.floor, .fptosi_sat, .fptoui_sat]! { if _ := vector_float_intrinsic_key(id, 1, 8) { assert false, 'two-width identity must not enter old key space' } }
	if _ := saturating_cast_vector(.floor, ScalarVectorValue{}, 32, 8, 1) { assert false }
	for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := saturating_cast_vector(.fptosi_sat, source, 32, 8, 1) { assert false } }
	println('AIR-VECTOR-SATURATING-CAST-STATES: ${checks} poison/undef lane checks; freeze, count/width/family/tag/name guards PASS')
}
