// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (p IRTypedProgram) vector_float_int_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !int {
	vector_operation_shape(p, IRTypedInstruction{...op, opcode: 0}, 1)!
	_, _, count := p.scalar_vector_type(op.result_type, false, remaining)!
	source := p.operands[op.operands_start]
	element, _, source_count := p.scalar_vector_type(source.type_index, mixed, 16)!
	if !mixed || count != source_count || p.types[element].kind !in [.half_t, .float_t]! || op.opcode !in [u32(3), 4]! { return error('AIR vector: floating to integer cast shape/opcode') }
	return count + p.vector_source_profile(stream, pools, bodies, scope, index, source, mixed, remaining - count)!
}
fn float_int_vector(source ScalarVectorValue, source_bits u32, dest_bits u32, count int, opcode u32) !ScalarVectorValue {
	if source_bits !in [u32(16), 32]! || dest_bits < 1 || dest_bits > 64 || count < 1 || count > 16 || opcode !in [u32(3), 4]! { return error('AIR vector: floating to integer lane shape') }
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		if source.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector: undef floating to integer lane') }
		input := source.lanes[lane]
		if input.aggregate || input.vector { return error('AIR vector: scalar floating to integer lane required') }
		result.lanes[lane] = if input.poison { IntegerValue{poison: true} } else if source_bits == 16 { binary16_to_integer(dest_bits, opcode == 4, u16(input.value))! } else { binary32_to_integer(dest_bits, opcode == 4, u32(input.value))! }
	}
	return result
}
fn (mut m IntegerMachine) float_int_vector_value(stream Stream, inst IRInstruction, op IRTypedInstruction) !IntegerValue {
	source := m.p.operands[op.operands_start]
	_, source_bits, count := m.p.scalar_vector_type(source.type_index, m.binary32, 16)!
	_, dest_bits, _ := m.p.scalar_vector_type(op.result_type, false, 16)!
	return m.store_vector_value(inst, float_int_vector(m.read_vector(stream, source)!, source_bits, dest_bits, count, op.opcode)!)!
}
