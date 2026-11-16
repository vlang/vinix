// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_vector_bitcast_preserves_raw_bits_and_snapshots() {
	mut checks := 0
	for bits in [u32(16), 32]! { for sample in 0 .. 65536 {
		mut source := ScalarVectorValue{}
		for lane in 0 .. 16 { word := if bits == 16 { u64((sample + lane) % 65536) } else { u64(u32(sample) * u32(0x9e3779b9) + u32(lane) * u32(0x01010101)) }; source.lanes[lane] = IntegerValue{value: word | ~constant_mask(bits)} }
		before := source; result := bitcast_vector(source, bits, 16)!
		for lane in 0 .. 16 { assert result.lanes[lane].value == source.lanes[lane].value & constant_mask(bits) && !result.lanes[lane].poison; checks++ }
		inserted_vector(result, 16, IntegerValue{}, IntegerValue{}, false)!; frozen_vector(result, 16)!
		assert source == before && result.undef == 0
	} }
	assert checks == 2097152
	println('AIR-VECTOR-BITCAST-VALUES: ${checks} raw-bit checks, all half encodings and deterministic float patterns, source masking and independent snapshots PASS')
}
fn test_vector_bitcast_lane_states_and_guards() {
	mut checks := 0
	for bits in [u32(16), 32]! { for count in 1 .. 17 { for target in 0 .. count {
		mut source := ScalarVectorValue{}; source.lanes[target] = IntegerValue{poison: true}
		result := bitcast_vector(source, bits, count)!
		for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); checks++ }
		assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
		source.undef = u16(1) << u32(target)
		if _ := bitcast_vector(source, bits, count) { assert false, 'undef source lane' }; checks++
	} } }
	for bits in [u32(0), 1, 15, 17, 31, 33, 64, 65]! { if _ := bitcast_vector(ScalarVectorValue{}, bits, 1) { assert false, 'width guard' } }
	for count in [0, 17] { if _ := bitcast_vector(ScalarVectorValue{}, 16, count) { assert false, 'count guard' } }
	for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := bitcast_vector(source, 16, 1) { assert false, 'lane tag' } }
	assert checks == 3264
	println('AIR-VECTOR-BITCAST-STATES: ${checks} poison/undef lane checks, freezes and shape/tag guards PASS')
}

fn test_reshaped_bitcast_half_encodings_and_raw_float_patterns() {
	mut checks := 0
	for sample in 0 .. 65536 {
		mut halves := ScalarVectorValue{}
		for lane in 0 .. 16 { halves.lanes[lane] = IntegerValue{value: u64((sample + lane * 257) % 65536) | 0xffffffffffff0000} }
		before := halves
		words := reshaped_bitcast_vector(halves, 16, 16, 32, 8)!
		back := reshaped_bitcast_vector(words, 32, 8, 16, 16)!
		for lane in 0 .. 8 { assert words.lanes[lane] == IntegerValue{value: (halves.lanes[lane * 2].value & 65535) + ((halves.lanes[lane * 2 + 1].value & 65535) * 65536)}; checks++ }
		for lane in 0 .. 16 { assert back.lanes[lane] == IntegerValue{value: halves.lanes[lane].value & 65535}; checks++ }
		assert halves == before
	}
	assert checks == 1572864
	println('AIR-VECTOR-RESHAPED-BITCAST: ${checks} packed/split raw lane checks, every half encoding, signaling payloads and immutable source snapshots PASS')
}

fn test_reshaped_bitcast_overlap_states_and_diagnostics() {
	mut checks := 0
	for source_bits in u32(1) .. 65 { for bits in [u32(16), 32]! { for source_count in 1 .. 17 {
		total := source_bits * u32(source_count)
		if total % bits != 0 || total / bits > 16 { continue }
		count := int(total / bits)
		for reverse in [false, true] {
			from_bits := if reverse { bits } else { source_bits }; from_count := if reverse { count } else { source_count }
			to_bits := if reverse { source_bits } else { bits }; to_count := if reverse { source_count } else { count }
			for target in 0 .. from_count {
				mut source := ScalarVectorValue{}
				source.lanes[target] = IntegerValue{value: ~u64(0), poison: true}
				result := reshaped_bitcast_vector(source, from_bits, from_count, to_bits, to_count)!
				frozen := frozen_vector(result, to_count)!
				for lane in 0 .. to_count {
					overlaps := u32(lane) * to_bits < u32(target + 1) * from_bits && u32(lane + 1) * to_bits > u32(target) * from_bits
					assert result.lanes[lane].poison == overlaps && frozen.lanes[lane] == IntegerValue{}; checks++
				}
				source.undef = u16(1) << u32(target)
				if _ := reshaped_bitcast_vector(source, from_bits, from_count, to_bits, to_count) { assert false } else { assert err.msg() == 'AIR vector: undef bitcast lane' }; checks++
			}
		}
	} } }
	for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] {
		mut source := ScalarVectorValue{}; source.lanes[1] = tag
		if _ := reshaped_bitcast_vector(source, 16, 2, 32, 1) { assert false } else { assert err.msg() == 'AIR vector: scalar bitcast lane required' }
	}
	if _ := reshaped_bitcast_vector(ScalarVectorValue{}, 16, 2, 32, 2) { assert false }
	println('AIR-VECTOR-RESHAPED-BITCAST-STATES: ${checks} integer/half/float-width overlap states, whole-source undef rejection, frozen results and stable diagnostics PASS')
}
