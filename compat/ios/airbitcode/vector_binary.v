// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (p IRTypedProgram) vector_binary_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !int {
	vector_operation_shape(p, IRTypedInstruction{...op, flags: 0, opcode: 0}, 2)!
	element, _, count := p.scalar_vector_type(op.result_type, mixed, remaining)!
	floating := p.types[element].kind in [.half_t, .float_t]!
	left := p.operands[op.operands_start]; right := p.operands[op.operands_start + 1]
	if left.type_index != op.result_type || right.type_index != op.result_type || (floating && (op.opcode !in [u32(0), 1, 2, 4, 6]! || op.flags != 0)) || (!floating && (op.opcode > 12 || op.flags & ~integer_binary_flag_mask(op.opcode) != 0)) { return error('AIR vector: binary types/opcode/flags') }
	left_work := p.vector_source_profile(stream, pools, bodies, scope, index, left, mixed, remaining - count)!
	right_work := p.vector_source_profile(stream, pools, bodies, scope, index, right, mixed, remaining - count - left_work)!
	return count + left_work + right_work
}
fn binary_vector(left ScalarVectorValue, right ScalarVectorValue, bits u32, count int, opcode u32, flags u64) !ScalarVectorValue {
	if count < 1 || count > 16 || bits < 1 || bits > 64 || opcode > 12 || flags & ~integer_binary_flag_mask(opcode) != 0 { return error('AIR vector: integer binary lanes/opcode/flags') }
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		if (left.undef | right.undef) & (u16(1) << u32(lane)) != 0 { return error('AIR vector: undef binary lane') }
		a := left.lanes[lane]; b := right.lanes[lane]
		if a.aggregate || a.vector || b.aggregate || b.vector { return error('AIR vector: scalar binary lanes required') }
		// Undefined division/remainder rejects the whole executed instruction,
		// following the scalar policy. Other poison remains local to each lane.
		result.lanes[lane] = integer_binary_flags(opcode, flags, bits, a, b)!
	}
	return result
}
fn (mut m IntegerMachine) binary_vector_value(stream Stream, inst IRInstruction, op IRTypedInstruction) !IntegerValue {
	left := m.read_vector(stream, m.p.operands[op.operands_start])!
	right := m.read_vector(stream, m.p.operands[op.operands_start + 1])!
	element, bits, count := m.p.scalar_vector_type(op.result_type, m.binary32, 16)!
	result := if m.p.types[element].kind in [.half_t, .float_t]! { floating_binary_vector(left, right, bits, count, op.opcode)! } else { binary_vector(left, right, bits, count, op.opcode, op.flags)! }
	return m.store_vector_value(inst, result)!
}
