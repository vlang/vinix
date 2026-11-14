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
