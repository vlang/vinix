// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// A per-bit oracle avoids the production mask/reconstruction formulas and
// signed host arithmetic at i64 boundaries.
fn vector_integer_cast_expected(opcode u32, flags u64, source_bits u32, dest_bits u32, word u64) (bool, u64) {
	negative := word >> (source_bits - 1) & 1
	mut poison := opcode == 1 && flags == 1 && negative != 0
	if opcode == 0 { for bit in dest_bits .. source_bits {
		value := word >> bit & 1
		if flags & 1 != 0 && value != 0 { poison = true }
		if flags & 2 != 0 && value != word >> (dest_bits - 1) & 1 { poison = true }
	} }
	mut result := u64(0)
	for bit in u32(0) .. dest_bits {
		value := if bit < source_bits { word >> bit & 1 } else if opcode == 2 { negative } else { u64(0) }
		result |= value << bit
	}
	return poison, result
}
fn test_vector_integer_cast_all_widths_values_flags_and_snapshots() {
	mut checks := 0
	for source_bits in u32(1) .. 65 { for dest_bits in u32(1) .. 65 {
		if source_bits == dest_bits { continue }
		words := [u64(0), 1, constant_mask(source_bits), u64(1) << (source_bits - 1), (u64(1) << (source_bits - 1)) - 1, (u64(1) << (source_bits - 1)) + 1, 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15]!
		for opcode in u32(0) .. 3 {
			if (opcode == 0) != (dest_bits < source_bits) { continue }
			for flags in u64(0) .. scalar_cast_flag_mask(opcode) + 1 { for sample in 0 .. 8 {
				mut source := ScalarVectorValue{}
				for lane in 0 .. 16 { source.lanes[lane] = IntegerValue{value: words[(sample + lane) % 8] | ~constant_mask(source_bits)} }
				before := source; result := cast_integer_vector(source, source_bits, dest_bits, 16, opcode, flags)!
				assert result.undef == 0
				for lane in 0 .. 16 {
					poison, value := vector_integer_cast_expected(opcode, flags, source_bits, dest_bits, source.lanes[lane].value)
					assert result.lanes[lane].poison == poison && (poison || result.lanes[lane].value == value); checks++
				}
				frozen_vector(result, 16)!; inserted_vector(result, 16, IntegerValue{}, IntegerValue{}, false)!
				assert source == before
			} }
		}
	} }
	assert checks == 1806336
	println('AIR-VECTOR-INTEGER-CAST-VALUES: ${checks} independent per-bit lane checks across every i1-i64 width pair and seven opcode/flag variants; source masking, sign extension, promise poison and immutable snapshots PASS')
}
fn test_vector_integer_cast_lane_states_and_guards() {
	mut checks := 0
	for source_bits in u32(1) .. 65 { for dest_bits in [u32(1), 64]! {
		if source_bits == dest_bits { continue }
		for opcode in u32(0) .. 3 { if (opcode == 0) != (dest_bits < source_bits) { continue }
			for flags in u64(0) .. scalar_cast_flag_mask(opcode) + 1 { for count in 1 .. 17 { for target in 0 .. count {
				mut source := ScalarVectorValue{}; source.lanes[target] = IntegerValue{poison: true}
				result := cast_integer_vector(source, source_bits, dest_bits, count, opcode, flags)!
				for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); checks++ }
				assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
				source.undef = u16(1) << u32(target)
				if _ := cast_integer_vector(source, source_bits, dest_bits, count, opcode, flags) { assert false, 'undef cast operand' }; checks++
			} } }
		}
	} }
	for count in [0, 17] { if _ := cast_integer_vector(ScalarVectorValue{}, 8, 16, count, 1, 0) { assert false, 'lane count' } }
	for widths in [[u32(0), 16]!, [u32(8), 0]!, [u32(65), 16]!, [u32(8), 65]!] { if _ := cast_integer_vector(ScalarVectorValue{}, widths[0], widths[1], 1, 0, 0) { assert false, 'width guard' } }
	for opcode in u32(0) .. 3 { for widths in [[u32(8), 8]!, [u32(8), 16]!, [u32(16), 8]!] {
		if widths[0] == widths[1] || ((opcode == 0) != (widths[1] < widths[0])) { if _ := cast_integer_vector(ScalarVectorValue{}, widths[0], widths[1], 1, opcode, 0) { assert false, 'direction guard' } }
	} }
	for opcode in u32(0) .. 3 { if _ := cast_integer_vector(ScalarVectorValue{}, if opcode == 0 { 16 } else { 8 }, if opcode == 0 { 8 } else { 16 }, 1, opcode, 4) { assert false, 'flag guard' } }
	if _ := cast_integer_vector(ScalarVectorValue{}, 8, 16, 1, 3, 0) { assert false, 'opcode guard' }
	for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := cast_integer_vector(source, 8, 16, 1, 1, 0) { assert false, 'scalar lane required' } }
	println('AIR-VECTOR-INTEGER-CAST-STATES: ${checks} poison/undef lane controls across all source widths and counts/lanes/variants; frozen results and shape/flag/opcode/tag guards PASS')
}
