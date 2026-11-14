// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_vector_int_float_exhaustive_small_integer_float_round_trips() {
	mut checks := 0
	for width in u32(1) .. 17 { for opcode in [u32(5), 6]! { for word in u64(0) .. u64(1) << width {
		mut source := ScalarVectorValue{}; source.lanes[0] = IntegerValue{value: word | ~constant_mask(width)}; before := source
		result := int_float_vector(source, width, 32, 1, opcode)!
		back := binary32_to_integer(width, opcode == 6, u32(result.lanes[0].value))!
		assert !result.lanes[0].poison && !back.poison && back.value == word && result.undef == 0 && source == before; checks++
	} } }
	assert checks == 262140
	println('AIR-VECTOR-INT-FLOAT-ROUNDTRIP: ${checks} exact signed/unsigned i1-i16 float round trips, source masking and immutable snapshots PASS')
}
fn test_vector_int_float_known_rounding_and_overflow() {
	// width, signed opcode, destination, integer bits, exact result bits.
	for row in [[u64(1), 6, 16, 1, 0xbc00]!, [u64(1), 5, 32, 1, 0x3f800000]!, [u64(64), 5, 16, 2049, 0x6800]!, [u64(64), 5, 16, 2051, 0x6802]!, [u64(64), 5, 16, 65519, 0x7bff]!, [u64(64), 5, 16, 65520, 0x7c00]!, [u64(64), 6, 16, 0xffffffffffff0011, 0xfbff]!, [u64(64), 6, 16, 0xffffffffffff0010, 0xfc00]!, [u64(64), 5, 32, 16777217, 0x4b800000]!, [u64(64), 5, 32, 16777219, 0x4b800002]!, [u64(64), 5, 32, 0xffffffffffffffff, 0x5f800000]!, [u64(64), 6, 32, 0x8000000000000000, 0xdf000000]!] {
		mut source := ScalarVectorValue{}; source.lanes[0] = IntegerValue{value: row[3]}; result := int_float_vector(source, u32(row[0]), u32(row[2]), 1, u32(row[1]))!; assert !result.lanes[0].poison && result.lanes[0].value == row[4], '${row}'
	}
	println('AIR-VECTOR-INT-FLOAT-PATTERNS: signed i1, ties, half overflow and i64 boundaries PASS')
}
fn test_vector_int_float_lane_states_and_guards() {
	mut checks := 0
	for width in u32(1) .. 65 { for dest in [u32(16), 32]! { for opcode in [u32(5), 6]! { for count in 1 .. 17 { for target in 0 .. count {
		mut source := ScalarVectorValue{}; source.lanes[target] = IntegerValue{poison: true}; result := int_float_vector(source, width, dest, count, opcode)!
		for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); checks++ }
		assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
		source.undef = u16(1) << u32(target); if _ := int_float_vector(source, width, dest, count, opcode) { assert false, 'undef cast source' }; checks++
	} } } } }
	for width in [u32(0), 65]! { if _ := int_float_vector(ScalarVectorValue{}, width, 32, 1, 5) { assert false, 'source width' } }
	for dest in [u32(0), 8, 64]! { if _ := int_float_vector(ScalarVectorValue{}, 64, dest, 1, 5) { assert false, 'destination width' } }
	for count in [0, 17] { if _ := int_float_vector(ScalarVectorValue{}, 64, 32, count, 5) { assert false, 'count' } }
	for opcode in [u32(0), 3, 4, 7, 8, 11]! { if _ := int_float_vector(ScalarVectorValue{}, 64, 32, 1, opcode) { assert false, 'opcode' } }
	for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := int_float_vector(source, 64, 32, 1, 5) { assert false, 'scalar lane' } }
	assert checks == 417792
	println('AIR-VECTOR-INT-FLOAT-STATES: ${checks} poison/undef lane checks across all source widths, both formats/signs and every count/lane; freeze and shape/tag guards PASS')
}
