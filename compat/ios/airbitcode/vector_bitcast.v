// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (p IRTypedProgram) vector_cast_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !int {
	if op.opcode in [u32(7), 8]! { return p.vector_precision_cast_profile(stream, pools, bodies, scope, index, op, mixed, remaining)! }
	if op.opcode != 11 { return p.vector_integer_cast_profile(stream, pools, bodies, scope, index, op, remaining)! }
	vector_operation_shape(p, IRTypedInstruction{...op, opcode: 0}, 1)!
	dest, dest_bits, count := p.scalar_vector_type(op.result_type, mixed, remaining)!
	source := p.operands[op.operands_start]
	element, source_bits, source_count := p.scalar_vector_type(source.type_index, mixed, 16)!
	floating_source := p.types[element].kind in [.half_t, .float_t]!
	floating_result := p.types[dest].kind in [.half_t, .float_t]!
	if !mixed || source_count != count || source_bits != dest_bits || floating_source == floating_result { return error('AIR vector: integer/floating bitcast shape') }
	return count + p.vector_source_profile(stream, pools, bodies, scope, index, source, mixed, remaining - count)!
}
fn bitcast_vector(source ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
	if bits !in [u32(16), 32]! || count < 1 || count > 16 { return error('AIR vector: bitcast lane shape') }
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		if source.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector: undef bitcast lane') }
		input := source.lanes[lane]
		if input.aggregate || input.vector { return error('AIR vector: scalar bitcast lane required') }
		// Reinterpret bits without floating arithmetic, including signaling NaNs.
		result.lanes[lane] = IntegerValue{value: input.value & constant_mask(bits), poison: input.poison}
	}
	return result
}
fn (mut m IntegerMachine) cast_vector_value(stream Stream, inst IRInstruction, op IRTypedInstruction) !IntegerValue {
	if op.opcode in [u32(7), 8]! { return m.precision_cast_vector_value(stream, inst, op)! }
	if op.opcode != 11 { return m.cast_integer_vector_value(stream, inst, op)! }
	source := m.read_vector(stream, m.p.operands[op.operands_start])!
	_, bits, count := m.p.scalar_vector_type(op.result_type, m.binary32, 16)!
	return m.store_vector_value(inst, bitcast_vector(source, bits, count)!)!
}
