// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (p IRTypedProgram) vector_integer_cast_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, remaining int) !int {
	vector_operation_shape(p, IRTypedInstruction{...op, flags: 0, opcode: 0}, 1)!
	_, dest_bits, count := p.scalar_vector_type(op.result_type, false, remaining)!
	source := p.operands[op.operands_start]
	_, source_bits, source_count := p.scalar_vector_type(source.type_index, false, 16)!
	if source_count != count || op.opcode > 2 || op.flags & ~scalar_cast_flag_mask(op.opcode) != 0 || (op.opcode == 0 && dest_bits >= source_bits) || (op.opcode != 0 && dest_bits <= source_bits) { return error('AIR vector: integer cast shape/opcode/flags/direction') }
	return count + p.vector_source_profile(stream, pools, bodies, scope, index, source, false, remaining - count)!
}
fn cast_integer_vector(source ScalarVectorValue, source_bits u32, dest_bits u32, count int, opcode u32, flags u64) !ScalarVectorValue {
	if count < 1 || count > 16 { return error('AIR vector: integer cast lane count') }
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		if source.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector: undef integer cast lane') }
		input := source.lanes[lane]
		if input.aggregate || input.vector { return error('AIR vector: scalar integer cast lane required') }
		result.lanes[lane] = scalar_integer_cast(opcode, flags, source_bits, dest_bits, input)!
	}
	return result
}
fn (mut m IntegerMachine) cast_integer_vector_value(stream Stream, inst IRInstruction, op IRTypedInstruction) !IntegerValue {
	operand := m.p.operands[op.operands_start]
	source := m.read_vector(stream, operand)!
	_, source_bits, count := m.p.scalar_vector_type(operand.type_index, false, 16)!
	_, dest_bits, _ := m.p.scalar_vector_type(op.result_type, false, 16)!
	return m.store_vector_value(inst, cast_integer_vector(source, source_bits, dest_bits, count, op.opcode, op.flags)!)!
}
