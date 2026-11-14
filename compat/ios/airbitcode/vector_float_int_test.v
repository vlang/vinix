// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Independent half oracle: exact f64 scaling, followed by a safe conversion
// of a nonnegative finite magnitude no larger than 65,504.
fn vector_half_integer_reference(raw u16, width u32, signed bool) IntegerValue {
	exponent := int((raw >> 10) & 31); fraction := raw & 1023
	if exponent == 31 { return IntegerValue{poison: true} }
	mut value := f64(if exponent == 0 { fraction } else { 1024 + fraction })
	scale := (if exponent == 0 { -14 } else { exponent - 15 }) - 10
	if scale < 0 { for _ in 0 .. -scale { value /= 2 } } else { for _ in 0 .. scale { value *= 2 } }
	magnitude := u64(value); negative := raw & 0x8000 != 0; mask := constant_mask(width)
	limit := if signed { if negative { u64(1) << (width - 1) } else { (u64(1) << (width - 1)) - 1 } } else { mask }
	if magnitude > limit || (!signed && negative && magnitude != 0) { return IntegerValue{poison: true} }
	return IntegerValue{value: if negative { (u64(0) - magnitude) & mask } else { magnitude }}
}
fn test_vector_float_int_all_half_encodings_and_integer_widths() {
	mut values := 0; mut poison := 0
	for width in u32(1) .. 65 { for opcode in [u32(3), 4]! { for raw in 0 .. 65536 {
		mut source := ScalarVectorValue{}; source.lanes[0] = IntegerValue{value: u64(raw) | 0xdeadbeef00000000}; before := source
		result := float_int_vector(source, 16, width, 1, opcode)!
		expected := vector_half_integer_reference(u16(raw), width, opcode == 4)
		assert result.lanes[0] == expected && result.undef == 0 && source == before, '${width} ${opcode} ${raw}'
		if expected.poison { poison++ } else { values++ }
	} } }
	assert values + poison == 8388608 && values > 0 && poison > 0
	println('AIR-VECTOR-FLOAT-INT-HALF: ${values + poison} independent exact half comparisons across i1-i64 (${values} values, ${poison} poison), source masking and snapshots PASS')
}
fn test_vector_float_int_fractional_and_wide_boundaries() {
	// destination, opcode, float encoding, poison tag, integer representation.
	for row in [[u64(8), 3, 0xbf7fffff, 0, 0]!, [u64(8), 3, 0xbf800000, 1, 0]!, [u64(8), 3, 0x437fffff, 0, 255]!, [u64(8), 3, 0x43800000, 1, 0]!, [u64(8), 4, 0xc300ffff, 0, 128]!, [u64(8), 4, 0xc3010000, 1, 0]!, [u64(8), 4, 0x42ffffff, 0, 127]!, [u64(8), 4, 0x43000000, 1, 0]!, [u64(64), 3, 0x5f7fffff, 0, 0xffffff0000000000]!, [u64(64), 3, 0x5f800000, 1, 0]!, [u64(64), 4, 0xdf000000, 0, 0x8000000000000000]!, [u64(64), 4, 0x5f000000, 1, 0]!, [u64(1), 4, 0xbf800000, 0, 1]!, [u64(1), 4, 0x3f800000, 1, 0]!] {
		mut source := ScalarVectorValue{}; source.lanes[0] = IntegerValue{value: row[2] | 0xfeedface00000000}; result := float_int_vector(source, 32, u32(row[0]), 1, u32(row[1]))!
		assert result.lanes[0].poison == (row[3] != 0) && (result.lanes[0].poison || result.lanes[0].value == row[4]), '${row}'
	}
	println('AIR-VECTOR-FLOAT-INT-BOUNDARIES: negative fractions, signed fractional minima, i1/i8/i64 limits and source masking PASS')
}
fn test_vector_float_int_lane_states_and_guards() {
	mut checks := 0
	for width in u32(1) .. 65 { for source_bits in [u32(16), 32]! { for opcode in [u32(3), 4]! { for count in 1 .. 17 { for target in 0 .. count {
		mut source := ScalarVectorValue{}; source.lanes[target] = IntegerValue{poison: true}; result := float_int_vector(source, source_bits, width, count, opcode)!
		for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); checks++ }
		assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
		source.undef = u16(1) << u32(target); if _ := float_int_vector(source, source_bits, width, count, opcode) { assert false, 'undef source' }; checks++
	} } } } }
	for width in [u32(0), 65]! { if _ := float_int_vector(ScalarVectorValue{}, 32, width, 1, 3) { assert false, 'destination width' } }
	for source in [u32(0), 8, 64]! { if _ := float_int_vector(ScalarVectorValue{}, source, 64, 1, 3) { assert false, 'source width' } }
	for count in [0, 17] { if _ := float_int_vector(ScalarVectorValue{}, 32, 64, count, 3) { assert false, 'lane count' } }
	for opcode in [u32(0), 1, 2, 5, 6, 7, 8, 11]! { if _ := float_int_vector(ScalarVectorValue{}, 32, 64, 1, opcode) { assert false, 'opcode' } }
	for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := float_int_vector(source, 32, 64, 1, 3) { assert false, 'scalar lane' } }
	assert checks == 417792
	println('AIR-VECTOR-FLOAT-INT-STATES: ${checks} poison/undef lane checks across all destinations, both source formats/signs and every count/lane, freeze and shape/tag guards PASS')
}
