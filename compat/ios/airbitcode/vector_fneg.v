// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (p IRTypedProgram) vector_fneg_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !int {
	vector_operation_shape(p, op, 1)!
	element, _, count := p.scalar_vector_type(op.result_type, mixed, remaining)!
	if !mixed || p.types[element].kind !in [.half_t, .float_t]! { return error('AIR vector: floating fneg required') }
	source := p.operands[op.operands_start]
	if source.type_index != op.result_type { return error('AIR vector: fneg type identity') }
	return count + p.vector_source_profile(stream, pools, bodies, scope, index, source, mixed, remaining - count)!
}
fn negated_vector(source ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
	if bits !in [u32(16), 32]! || count < 1 || count > 16 { return error('AIR vector: fneg lane shape') }
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		if source.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector: undef fneg lane') }
		input := source.lanes[lane]
		if input.aggregate || input.vector { return error('AIR vector: scalar fneg lane required') }
		// fneg changes only the sign, even for signaling NaNs and signed zeros.
		result.lanes[lane] = IntegerValue{value: (input.value ^ (u64(1) << (bits - 1))) & constant_mask(bits), poison: input.poison}
	}
	return result
}
fn (mut m IntegerMachine) fneg_vector_value(stream Stream, inst IRInstruction, op IRTypedInstruction) !IntegerValue {
	source := m.read_vector(stream, m.p.operands[op.operands_start])!
	_, bits, count := m.p.scalar_vector_type(op.result_type, m.binary32, 16)!
	return m.store_vector_value(inst, negated_vector(source, bits, count)!)!
}
