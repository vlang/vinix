// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const max_vector_update_results = 4096

struct ScalarVectorValue {
mut:
	lanes [16]IntegerValue
	undef u16
}
fn vector_operation_shape(p IRTypedProgram, op IRTypedInstruction, arity int) ! {
	if op.flags != 0 || op.opcode != 0 || op.operands_count != arity || op.operands_start < 0 || op.operands_start > p.operands.len || op.operands_count > p.operands.len - op.operands_start || op.indices_count != 0 || op.targets_count != 0 { return error('AIR vector: operation shape/flags') }
}
fn (p IRTypedProgram) vector_source_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, source IRTypedOperand, mixed bool, remaining int) !int {
	_, _, count := p.scalar_vector_type(source.type_index, mixed, remaining)!
	s := bodies.scopes[scope]
	if source.number < s.base_id { return p.constant_vector_profile(stream, pools, bodies, scope, source, mixed, remaining)! }
	slot := u64(source.number) - s.base_id
	if slot >= u64(s.results_count) || s.results_start < 0 || s.results_start > bodies.results.len || slot >= u64(bodies.results.len - s.results_start) { return error('AIR vector: source result slot') }
	producer := bodies.results[s.results_start + int(slot)]
	if producer < s.instructions_start || producer >= index || producer >= p.instructions.len || producer >= bodies.instructions.len { return error('AIR vector: earlier construction required') }
	op := p.instructions[producer]; inst := bodies.instructions[producer]
	if inst.scope != scope || !inst.has_result || inst.next_value != source.number || op.status != .decoded || op.result_type != source.type_index || inst.record < 0 || inst.record >= stream.records.len || !p.vector_construction(stream.records[inst.record].code, op) { return error('AIR vector: construction source required') }
	return count
}
fn (p IRTypedProgram) vector_extract_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !int {
	vector_operation_shape(p, op, 2)!
	source := p.operands[op.operands_start]
	if source.number < bodies.scopes[scope].base_id { return p.constant_extract_profile(stream, pools, bodies, scope, op, mixed, remaining)! }
	element, _, _ := p.scalar_vector_type(source.type_index, mixed, remaining)!
	if op.result_type != element { return error('AIR vector: extract result type') }
	p.integer_bits(p.operands[op.operands_start + 1].type_index)!
	return p.vector_source_profile(stream, pools, bodies, scope, index, source, mixed, remaining)!
}
fn (p IRTypedProgram) vector_insert_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !int {
	vector_operation_shape(p, op, 3)!
	source := p.operands[op.operands_start]
	element, _, _ := p.scalar_vector_type(source.type_index, mixed, remaining)!
	if op.result_type != source.type_index || p.operands[op.operands_start + 1].type_index != element { return error('AIR vector: insertion type identity') }
	p.integer_bits(p.operands[op.operands_start + 2].type_index)!
	return p.vector_source_profile(stream, pools, bodies, scope, index, source, mixed, remaining)!
}
fn inserted_vector(source ScalarVectorValue, count int, index IntegerValue, lane IntegerValue, undef bool) !ScalarVectorValue {
	if count < 1 || count > 16 || lane.aggregate || lane.vector { return error('AIR vector: insertion value/count') }
	mut result := source
	if index.poison || index.value >= u64(count) {
		result.undef = 0
		for i in 0 .. count { result.lanes[i] = IntegerValue{poison: true} }
	} else {
		i := int(index.value); bit := u16(1) << u32(i)
		result.lanes[i] = lane
		if undef { result.undef |= bit } else { result.undef &= ~bit }
	}
	return result
}
fn (m &IntegerMachine) read_vector(stream Stream, source IRTypedOperand) !ScalarVectorValue {
	s := m.bodies.scopes[m.scope]
	if source.number >= s.base_id {
		slot := u64(source.number) - s.base_id
		if slot >= u64(m.values.len) || !m.known[int(slot)] { return error('AIR vector: result unavailable on executed path') }
		value := m.values[int(slot)]
		if !value.vector || value.value >= u64(m.vectors.len) { return error('AIR vector: vector slot required') }
		return m.vectors[int(value.value)]
	}
	c := m.p.extracted_constant(m.pools, m.bodies, m.scope, source)!
	_, bits, count := m.p.scalar_vector_type(source.type_index, m.binary32, 16)!
	mut result := ScalarVectorValue{}
	for i in 0 .. count {
		mut lane := c
		if c.kind == .data { result.lanes[i] = IntegerValue{value: m.pools.words[c.words_start + i] & constant_mask(bits)}; continue }
		if c.kind == .aggregate { numbers := ir_values(stream, stream.records[c.record]); value := m.pools.lookup(c.scope, numbers[i])!; lane = m.pools.constants[value.constant_index] }
		if lane.kind == .undef { result.undef |= u16(1) << u32(i) } else { result.lanes[i] = extracted_scalar_value(m.pools, lane, bits)! }
	}
	return result
}
// Static construction slots are reused on loop visits. Scalars keep their
// existing result slots; vector storage is allocated only for constructions.
fn (mut m IntegerMachine) seed_vector_slots(stream Stream) ! {
	if m.vectors.len == 0 { return }
	s := m.bodies.scopes[m.scope]; mut next := 0
	for index in s.instructions_start .. s.instructions_start + s.instructions_count {
		inst := m.bodies.instructions[index]
		if !m.p.vector_construction(stream.records[inst.record].code, m.p.instructions[index]) { continue }
		if next >= m.vectors.len || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(m.values.len) { return error('AIR vector: insertion slot count') }
		m.values[int(inst.next_value - s.base_id)] = IntegerValue{vector: true, value: u64(next)}; next++
	}
	if next != m.vectors.len { return error('AIR vector: insertion slot count') }
}
fn (mut m IntegerMachine) insert_vector_value(stream Stream, inst IRInstruction, op IRTypedInstruction) !IntegerValue {
	source := m.read_vector(stream, m.p.operands[op.operands_start])!
	operand := m.p.operands[op.operands_start + 1]
	mut undef := false
	if operand.number < m.bodies.scopes[m.scope].base_id { v := m.pools.lookup(m.scope, operand.number)!; undef = v.kind == .constant && m.pools.constants[v.constant_index].kind == .undef }
	lane := if undef { IntegerValue{} } else { m.read(op.operands_start + 1)! }
	index := m.read(op.operands_start + 2)!
	count := int(m.p.types[op.result_type].count)
	result := inserted_vector(source, count, index, lane, undef)!
	return m.store_vector_value(inst, result)!
}
fn (mut m IntegerMachine) store_vector_value(inst IRInstruction, result ScalarVectorValue) !IntegerValue {
	slot := int(inst.next_value - m.bodies.scopes[m.scope].base_id); tag := m.values[slot]
	if !tag.vector || tag.value >= u64(m.vectors.len) { return error('AIR vector: insertion storage slot') }
	m.vectors[int(tag.value)] = result
	return tag
}
