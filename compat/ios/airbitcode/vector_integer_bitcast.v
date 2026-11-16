// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn integer_vector_bitcast_shape(source_bits u32, source_count int, bits u32, count int) ! {
	if source_bits < 1 || source_bits > 64 || bits < 1 || bits > 64 || source_count < 1 || source_count > 16 || count < 1 || count > 16 || source_bits * u32(source_count) != bits * u32(count) { return error('AIR vector: integer bitcast shape') }
}

fn (p IRTypedProgram) vector_integer_bitcast_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, remaining int) !int {
	vector_operation_shape(p, IRTypedInstruction{...op, opcode: 0}, 1)!
	if op.opcode != 11 { return error('AIR vector: integer bitcast opcode') }
	_, bits, count := p.scalar_vector_type(op.result_type, false, remaining)!
	source := p.operands[op.operands_start]
	_, source_bits, source_count := p.scalar_vector_type(source.type_index, false, 16)!
	integer_vector_bitcast_shape(source_bits, source_count, bits, count)!
	return count + p.vector_source_profile(stream, pools, bodies, scope, index, source, false, remaining - count)!
}

// Little-endian packed bit positions, without byte padding between lanes.
// A destination lane is poison if any overlapping source lane is poison.
fn bitcast_integer_vector(source ScalarVectorValue, source_bits u32, source_count int, bits u32, count int) !ScalarVectorValue {
	integer_vector_bitcast_shape(source_bits, source_count, bits, count)!
	for lane in 0 .. source_count {
		if source.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector: undef integer bitcast lane') }
		if source.lanes[lane].aggregate || source.lanes[lane].vector { return error('AIR vector: scalar integer bitcast lane required') }
	}
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		mut word := u64(0)
		mut poison := false
		mut offset := u32(0)
		for offset < bits {
			position := u32(lane) * bits + offset
			input := source.lanes[position / source_bits]
			start := position % source_bits
			length := if source_bits - start < bits - offset { source_bits - start } else { bits - offset }
			word |= ((input.value >> start) & constant_mask(length)) << offset
			poison = poison || input.poison
			offset += length
		}
		result.lanes[lane] = IntegerValue{value: word, poison: poison}
	}
	return result
}

fn (mut m IntegerMachine) integer_bitcast_vector_value(stream Stream, inst IRInstruction, op IRTypedInstruction) !IntegerValue {
	operand := m.p.operands[op.operands_start]
	source := m.read_vector(stream, operand)!
	_, source_bits, source_count := m.p.scalar_vector_type(operand.type_index, false, 16)!
	_, bits, count := m.p.scalar_vector_type(op.result_type, false, 16)!
	return m.store_vector_value(inst, bitcast_integer_vector(source, source_bits, source_count, bits, count)!)!
}
