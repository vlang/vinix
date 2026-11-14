// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (p IRTypedProgram) vector_int_float_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !int {
	vector_operation_shape(p, IRTypedInstruction{...op, opcode: 0}, 1)!
	dest, _, count := p.scalar_vector_type(op.result_type, mixed, remaining)!
	source := p.operands[op.operands_start]
	_, _, source_count := p.scalar_vector_type(source.type_index, false, 16)!
	if !mixed || count != source_count || p.types[dest].kind !in [.half_t, .float_t]! || op.opcode !in [u32(5), 6]! { return error('AIR vector: integer to floating cast shape/opcode') }
	return count + p.vector_source_profile(stream, pools, bodies, scope, index, source, false, remaining - count)!
}
fn int_float_vector(source ScalarVectorValue, source_bits u32, dest_bits u32, count int, opcode u32) !ScalarVectorValue {
	if source_bits < 1 || source_bits > 64 || dest_bits !in [u32(16), 32]! || count < 1 || count > 16 || opcode !in [u32(5), 6]! { return error('AIR vector: integer to floating lane shape') }
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		if source.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector: undef integer to floating lane') }
		input := source.lanes[lane]
		if input.aggregate || input.vector { return error('AIR vector: scalar integer to floating lane required') }
		result.lanes[lane] = if input.poison { IntegerValue{poison: true} } else { IntegerValue{value: if dest_bits == 16 { u64(binary16_from_integer(source_bits, opcode == 6, input.value)!) } else { u64(binary32_from_integer(source_bits, opcode == 6, input.value)!) }} }
	}
	return result
}
fn (mut m IntegerMachine) int_float_vector_value(stream Stream, inst IRInstruction, op IRTypedInstruction) !IntegerValue {
	source := m.p.operands[op.operands_start]
	_, source_bits, count := m.p.scalar_vector_type(source.type_index, false, 16)!
	_, dest_bits, _ := m.p.scalar_vector_type(op.result_type, m.binary32, 16)!
	return m.store_vector_value(inst, int_float_vector(m.read_vector(stream, source)!, source_bits, dest_bits, count, op.opcode)!)!
}
