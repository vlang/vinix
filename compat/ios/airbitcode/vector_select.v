// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (p IRTypedProgram) vector_select_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !int {
	vector_operation_shape(p, op, 3)!
	_, _, count := p.scalar_vector_type(op.result_type, mixed, remaining)!
	left := p.operands[op.operands_start]; right := p.operands[op.operands_start + 1]
	condition := p.operands[op.operands_start + 2]
	if left.type_index != op.result_type || right.type_index != op.result_type { return error('AIR vector: select arm types') }
	mut condition_work := 0
	if p.gep_type(condition.type_index)!.kind == .vector_t {
		element, _, lanes := p.scalar_vector_type(condition.type_index, false, remaining - count)!
		if lanes != count || p.integer_bits(element)! != 1 { return error('AIR vector: matching i1 select condition required') }
		condition_work = p.vector_source_profile(stream, pools, bodies, scope, index, condition, false, remaining - count)!
	} else if p.integer_bits(condition.type_index)! != 1 { return error('AIR vector: i1 select condition required') }
	left_work := p.vector_source_profile(stream, pools, bodies, scope, index, left, mixed, remaining - count - condition_work)!
	right_work := p.vector_source_profile(stream, pools, bodies, scope, index, right, mixed, remaining - count - condition_work - left_work)!
	return count + condition_work + left_work + right_work
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
	if m.p.types[m.p.operands[op.operands_start + 2].type_index].kind == .vector_t { return m.select_vector_lanes(stream, inst, op)! }
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

// Only arms selected by at least one defined condition lane are needed.
fn vector_select_arms(condition ScalarVectorValue, count int) !(bool, bool) {
	if count < 1 || count > 16 { return error('AIR vector: select lane count') }
	mut left := false; mut right := false
	for lane in 0 .. count {
		if condition.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector: undef select condition lane') }
		c := condition.lanes[lane]
		if c.aggregate || c.vector { return error('AIR vector: scalar condition lane required') }
		if c.poison { continue }
		if c.value & 1 != 0 { left = true } else { right = true }
	}
	return left, right
}
fn selected_vector_lanes(left ScalarVectorValue, right ScalarVectorValue, condition ScalarVectorValue, count int) !ScalarVectorValue {
	vector_select_arms(condition, count)!
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		if condition.lanes[lane].poison { result.lanes[lane] = IntegerValue{poison: true}; continue }
		source := if condition.lanes[lane].value & 1 != 0 { left } else { right }
		result.lanes[lane] = source.lanes[lane]
		result.undef |= source.undef & (u16(1) << u32(lane))
	}
	return result
}
fn (mut m IntegerMachine) select_vector_lanes(stream Stream, inst IRInstruction, op IRTypedInstruction) !IntegerValue {
	condition := m.read_vector(stream, m.p.operands[op.operands_start + 2])!
	count := int(m.p.types[op.result_type].count)
	need_left, need_right := vector_select_arms(condition, count)!
	left := if need_left { m.read_vector(stream, m.p.operands[op.operands_start])! } else { ScalarVectorValue{} }
	right := if need_right { m.read_vector(stream, m.p.operands[op.operands_start + 1])! } else { ScalarVectorValue{} }
	return m.store_vector_value(inst, selected_vector_lanes(left, right, condition, count)!)!
}
