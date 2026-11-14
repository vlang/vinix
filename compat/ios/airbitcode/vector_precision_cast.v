// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (p IRTypedProgram) vector_precision_cast_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !int {
	vector_operation_shape(p, IRTypedInstruction{...op, opcode: 0}, 1)!
	dest, _, count := p.scalar_vector_type(op.result_type, mixed, remaining)!
	source := p.operands[op.operands_start]
	element, _, source_count := p.scalar_vector_type(source.type_index, mixed, 16)!
	if !mixed || count != source_count || (op.opcode == 7 && (p.types[element].kind != .float_t || p.types[dest].kind != .half_t)) || (op.opcode == 8 && (p.types[element].kind != .half_t || p.types[dest].kind != .float_t)) || op.opcode !in [u32(7), 8]! { return error('AIR vector: precision cast shape/direction') }
	return count + p.vector_source_profile(stream, pools, bodies, scope, index, source, mixed, remaining - count)!
}
fn precision_cast_vector(source ScalarVectorValue, source_bits u32, count int, opcode u32) !ScalarVectorValue {
	if count < 1 || count > 16 || (opcode == 7 && source_bits != 32) || (opcode == 8 && source_bits != 16) || opcode !in [u32(7), 8]! { return error('AIR vector: precision cast lane shape') }
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		if source.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector: undef precision cast lane') }
		input := source.lanes[lane]
		if input.aggregate || input.vector { return error('AIR vector: scalar precision cast lane required') }
		result.lanes[lane] = if input.poison { IntegerValue{poison: true} } else { IntegerValue{value: if opcode == 7 { u64(binary16_from_binary32(u32(input.value))) } else { u64(binary16_to_binary32(u16(input.value))) }} }
	}
	return result
}
fn (mut m IntegerMachine) precision_cast_vector_value(stream Stream, inst IRInstruction, op IRTypedInstruction) !IntegerValue {
	source := m.p.operands[op.operands_start]
	_, bits, count := m.p.scalar_vector_type(source.type_index, m.binary32, 16)!
	return m.store_vector_value(inst, precision_cast_vector(m.read_vector(stream, source)!, bits, count, op.opcode)!)!
}
