// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Check the normalized indexes against the original constant as well as their
// range. Poison and legacy undef mask entries both produce poison lanes.
fn (p IRTypedProgram) shuffle_constant_lane(stream Stream, pools IRConstantPools, c IRConstant, lane int, limit u64) !u32 {
	if c.kind in [.poison, .undef]! { return ~u32(0) }
	if c.kind == .zero { return 0 }
	if c.kind == .data { return shuffle_lane(pools.words[c.words_start + lane], limit)! }
	if c.kind == .aggregate {
		numbers := ir_values(stream, stream.records[c.record]); v := pools.lookup(c.scope, numbers[lane])!
		scalar := pools.constants[v.constant_index]
		if scalar.kind in [.poison, .undef]! { return ~u32(0) }
		return shuffle_lane(extracted_scalar_value(pools, scalar, 32)!.value, limit)!
	}
	return shuffle_lane(extracted_scalar_value(pools, c, 32)!.value, limit)!
}
fn (p IRTypedProgram) vector_shuffle_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !int {
	vector_operation_shape(p, IRTypedInstruction{...op, indices_count: 0}, 3)!
	element, _, count := p.scalar_vector_type(op.result_type, mixed, remaining)!
	if op.indices_count != count || op.indices_start < 0 || op.indices_start > p.indices.len || count > p.indices.len - op.indices_start { return error('AIR vector: shuffle mask range') }
	left := p.operands[op.operands_start]; right := p.operands[op.operands_start + 1]; mask := p.operands[op.operands_start + 2]
	input_element, _, input_count := p.scalar_vector_type(left.type_index, mixed, 16)!
	if right.type_index != left.type_index || op.source_type != left.type_index || input_element != element { return error('AIR vector: shuffle type identity') }
	mask_element, _, mask_count := p.scalar_vector_type(mask.type_index, false, 16)!
	if p.integer_bits(mask_element)! != 32 || mask_count != count { return error('AIR vector: i32 shuffle mask shape') }
	p.constant_vector_profile(stream, pools, bodies, scope, mask, false, 16)!
	c := p.extracted_constant(pools, bodies, scope, mask)!
	for lane in 0 .. count {
		selected := p.indices[op.indices_start + lane]
		if selected != p.shuffle_constant_lane(stream, pools, c, lane, u64(input_count * 2))! || (selected != ~u32(0) && selected >= u32(input_count * 2)) { return error('AIR vector: shuffle mask identity/range') }
	}
	left_work := p.vector_source_profile(stream, pools, bodies, scope, index, left, mixed, remaining - count)!
	right_work := p.vector_source_profile(stream, pools, bodies, scope, index, right, mixed, remaining - count - left_work)!
	return count + left_work + right_work
}
fn shuffled_vector(left ScalarVectorValue, right ScalarVectorValue, count int, mask []u32) !ScalarVectorValue {
	if count < 1 || count > 16 || mask.len < 1 || mask.len > 16 { return error('AIR vector: shuffle counts') }
	mut result := ScalarVectorValue{}
	for lane, selected in mask {
		if selected == ~u32(0) { result.lanes[lane] = IntegerValue{poison: true}; continue }
		if selected >= u32(count * 2) { return error('AIR vector: shuffle lane range') }
		i := int(selected) % count; source := if selected < u32(count) { left } else { right }
		result.lanes[lane] = source.lanes[i]
		if source.undef & (u16(1) << u32(i)) != 0 { result.undef |= u16(1) << u32(lane) }
	}
	return result
}
fn (mut m IntegerMachine) shuffle_vector_value(stream Stream, inst IRInstruction, op IRTypedInstruction) !IntegerValue {
	left := m.read_vector(stream, m.p.operands[op.operands_start])!
	right := m.read_vector(stream, m.p.operands[op.operands_start + 1])!
	result := shuffled_vector(left, right, int(m.p.types[op.source_type].count), m.p.indices[op.indices_start..op.indices_start + op.indices_count])!
	return m.store_vector_value(inst, result)!
}
