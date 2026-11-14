// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_vector_precision_cast_all_half_round_trips_and_snapshots() {
	mut checks := 0
	for batch in 0 .. 4096 {
		mut source := ScalarVectorValue{}
		for lane in 0 .. 16 { source.lanes[lane] = IntegerValue{value: u64(batch * 16 + lane) | 0xffffffffffff0000} }
		before := source; wide := precision_cast_vector(source, 16, 16, 8)!; narrow := precision_cast_vector(wide, 32, 16, 7)!
		for lane in 0 .. 16 { raw := u64(batch * 16 + lane); assert !wide.lanes[lane].poison && !narrow.lanes[lane].poison && narrow.lanes[lane].value == if raw & 0x7fff > 0x7c00 { u64(0x7e00) } else { raw }; checks++ }
		inserted_vector(wide, 16, IntegerValue{}, IntegerValue{}, false)!; frozen_vector(narrow, 16)!
		assert source == before && wide.undef == 0 && narrow.undef == 0
	}
	for row in [[u32(0x33000000), 0]!, [u32(0x33000001), 1]!, [u32(0x33c00000), 2]!, [u32(0x387fe000), 0x400]!, [u32(0x3f801000), 0x3c00]!, [u32(0x3f801001), 0x3c01]!, [u32(0x3f803000), 0x3c02]!, [u32(0x477ff000), 0x7c00]!, [u32(0xc77ff000), 0xfc00]!, [u32(0x80000001), 0x8000]!, [u32(0xff800001), 0x7e00]!] { mut source := ScalarVectorValue{}; source.lanes[0] = IntegerValue{value: u64(row[0]) | 0xffffffff00000000}; assert precision_cast_vector(source, 32, 1, 7)!.lanes[0].value == row[1]; checks++ }
	assert checks == 65547
	println('AIR-VECTOR-PRECISION-VALUES: ${checks} exhaustive half round trips, source masking, tie/subnormal/overflow/NaN patterns and immutable snapshots PASS')
}
fn test_vector_precision_cast_states_and_guards() {
	mut checks := 0
	for bits in [u32(16), 32]! { for count in 1 .. 17 { for target in 0 .. count {
		opcode := if bits == 16 { u32(8) } else { u32(7) }; mut source := ScalarVectorValue{}; source.lanes[target] = IntegerValue{poison: true}
		result := precision_cast_vector(source, bits, count, opcode)!
		for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); checks++ }
		assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
		source.undef = u16(1) << u32(target); if _ := precision_cast_vector(source, bits, count, opcode) { assert false, 'undef precision operand' }; checks++
	} } }
	for bits in [u32(0), 1, 15, 16, 17, 31, 32, 33, 64, 65]! { for opcode in [u32(0), 7, 8, 11]! { if (opcode == 7 && bits == 32) || (opcode == 8 && bits == 16) { continue }; if _ := precision_cast_vector(ScalarVectorValue{}, bits, 1, opcode) { assert false, 'width/direction/opcode' } } }
	for count in [0, 17] { if _ := precision_cast_vector(ScalarVectorValue{}, 16, count, 8) { assert false, 'lane count' } }
	for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := precision_cast_vector(source, 16, 1, 8) { assert false, 'scalar lane' } }
	assert checks == 3264
	println('AIR-VECTOR-PRECISION-STATES: ${checks} poison/undef lane controls, freezes and shape/tag guards PASS')
}
