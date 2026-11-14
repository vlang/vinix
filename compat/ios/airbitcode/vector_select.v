// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (p IRTypedProgram) vector_select_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !int {
	vector_operation_shape(p, op, 3)!
	_, _, count := p.scalar_vector_type(op.result_type, mixed, remaining)!
	left := p.operands[op.operands_start]; right := p.operands[op.operands_start + 1]
	if left.type_index != op.result_type || right.type_index != op.result_type || p.integer_bits(p.operands[op.operands_start + 2].type_index)! != 1 { return error('AIR vector: scalar-i1 select types') }
	left_work := p.vector_source_profile(stream, pools, bodies, scope, index, left, mixed, remaining - count)!
	right_work := p.vector_source_profile(stream, pools, bodies, scope, index, right, mixed, remaining - count - left_work)!
	return count + left_work + right_work
}
fn selected_vector(left ScalarVectorValue, right ScalarVectorValue, condition IntegerValue, count int) !ScalarVectorValue {
	if count < 1 || count > 16 || condition.aggregate || condition.vector { return error('AIR vector: select count/condition') }
	if condition.poison {
		mut result := ScalarVectorValue{}
		for lane in 0 .. count { result.lanes[lane] = IntegerValue{poison: true} }
		return result
	}
	return if condition.value & 1 != 0 { left } else { right }
}
fn (mut m IntegerMachine) select_vector_value(stream Stream, inst IRInstruction, op IRTypedInstruction) !IntegerValue {
	condition := m.read(op.operands_start + 2)!
	mut left := ScalarVectorValue{}; mut right := ScalarVectorValue{}
	// Only the chosen arm is read. Literal undef lanes stay tagged until a
	// later extraction; an undef condition is rejected by the scalar reader.
	if !condition.poison {
		if condition.value & 1 != 0 { left = m.read_vector(stream, m.p.operands[op.operands_start])! }
		else { right = m.read_vector(stream, m.p.operands[op.operands_start + 1])! }
	}
	return m.store_vector_value(inst, selected_vector(left, right, condition, int(m.p.types[op.result_type].count))!)!
}
