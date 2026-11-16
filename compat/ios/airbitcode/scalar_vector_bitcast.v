// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// A scalar contributes one packed lane. Vector destinations use existing
// construction slots; scalar destinations retain their ordinary SSA slot.
fn (p IRTypedProgram) scalar_vector_bitcast(op IRTypedInstruction) bool {
	if op.opcode != 11 || op.operands_count != 1 || op.operands_start < 0 || op.operands_start >= p.operands.len || op.result_type < 0 || op.result_type >= p.types.len { return false }
	source := p.operands[op.operands_start].type_index
	if source < 0 || source >= p.types.len { return false }
	return (p.types[source].kind == .vector_t) != (p.types[op.result_type].kind == .vector_t)
}

fn (p IRTypedProgram) scalar_vector_bitcast_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !int {
	vector_operation_shape(p, IRTypedInstruction{...op, opcode: 0}, 1)!
	if !p.scalar_vector_bitcast(op) { return error('AIR vector: scalar/vector bitcast shape') }
	source := p.operands[op.operands_start]
	if p.types[op.result_type].kind == .vector_t {
		_, bits, count := p.scalar_vector_type(op.result_type, mixed, remaining)!
		source_bits := p.execution_bits(source.type_index, mixed)!
		integer_vector_bitcast_shape(source_bits, 1, bits, count)!
		if remaining <= count { return error('AIR vector: constant lane work limit') }
		return count + 1
	}
	bits := p.execution_bits(op.result_type, mixed)!
	_, source_bits, source_count := p.scalar_vector_type(source.type_index, mixed, 16)!
	integer_vector_bitcast_shape(source_bits, source_count, bits, 1)!
	return 1 + p.vector_source_profile(stream, pools, bodies, scope, index, source, mixed, remaining - 1)!
}

fn (mut m IntegerMachine) scalar_vector_bitcast_value(stream Stream, inst IRInstruction, op IRTypedInstruction) !IntegerValue {
	operand := m.p.operands[op.operands_start]
	if m.p.types[op.result_type].kind == .vector_t {
		input := m.read(op.operands_start)!
		source_bits := m.p.execution_bits(operand.type_index, m.binary32)!
		_, bits, count := m.p.scalar_vector_type(op.result_type, m.binary32, 16)!
		mut source := ScalarVectorValue{}
		source.lanes[0] = input
		return m.store_vector_value(inst, reshaped_bitcast_vector(source, source_bits, 1, bits, count)!)!
	}
	source := m.read_vector(stream, operand)!
	_, source_bits, count := m.p.scalar_vector_type(operand.type_index, m.binary32, 16)!
	bits := m.p.execution_bits(op.result_type, m.binary32)!
	result := reshaped_bitcast_vector(source, source_bits, count, bits, 1)!
	return result.lanes[0]
}
