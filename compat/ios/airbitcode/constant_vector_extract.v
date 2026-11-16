// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const max_extracted_constant_lanes = 16

fn (p IRTypedProgram) extracted_constant(pools IRConstantPools, bodies IRFunctionBodies, scope int, operand IRTypedOperand) !IRConstant {
	if operand.number >= bodies.scopes[scope].base_id { return error('AIR vector: literal vector required') }
	value := pools.lookup(scope, operand.number)!
	if value.kind != .constant || value.type_index != operand.type_index { return error('AIR vector: matching constant required') }
	return pools.constants[value.constant_index]
}
fn extracted_scalar_constant(pools IRConstantPools, c IRConstant, element int, bits u32, integer bool) ! {
	if c.type_index != element || c.splat || c.bits != bits { return error('AIR vector: scalar lane type') }
	if c.kind in [.zero, .undef, .poison]! { return }
	if c.kind != if integer { IRConstantKind.integer } else { IRConstantKind.floating } || c.words_count != 1 || c.words_start < 0 || c.words_start >= pools.words.len { return error('AIR vector: materialized scalar lane required') }
}
fn (p IRTypedProgram) scalar_vector_type(type_index int, mixed bool, remaining int) !(int, u32, int) {
	if type_index < 0 || type_index >= p.types.len { return error('AIR vector: source type') }
	vector := p.types[type_index]
	if vector.kind != .vector_t || vector.scalable || vector.count < 1 || vector.count > max_extracted_constant_lanes || vector.refs_count != 1 || vector.refs_start < 0 || vector.refs_start >= p.references.len { return error('AIR vector: fixed 1..16 lanes required') }
	if remaining < 0 || vector.count > u64(remaining) { return error('AIR vector: constant lane work limit') }
	element := p.references[vector.refs_start]
	bits := p.execution_bits(element, mixed)!
	return element, bits, int(vector.count)
}
// Validate every lane, including unselected lanes and inactive blocks.
fn (p IRTypedProgram) constant_vector_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, source IRTypedOperand, mixed bool, remaining int) !int {
	element, bits, count := p.scalar_vector_type(source.type_index, mixed, remaining)!
	c := p.extracted_constant(pools, bodies, scope, source)!
	if c.kind in [.integer, .floating]! {
		if !c.splat || c.bits != bits || c.words_count != 1 || c.words_start < 0 || c.words_start >= pools.words.len || c.kind != if p.types[element].kind == .integer_t { IRConstantKind.integer } else { IRConstantKind.floating } { return error('AIR vector: scalar splat required') }
	} else if c.splat { return error('AIR vector: invalid splat kind') }
	else if c.kind == .data {
		if c.bits != bits || c.words_count != count || c.words_start < 0 || c.words_start > pools.words.len || c.words_count > pools.words.len - c.words_start { return error('AIR vector: data lane range') }
	} else if c.kind == .aggregate {
		if c.record < 0 || c.record >= stream.records.len { return error('AIR vector: lane record') }
		values := ir_values(stream, stream.records[c.record])
		if values.len != count { return error('AIR vector: aggregate lane count') }
		for number in values {
			lane := pools.lookup(c.scope, number)!
			if lane.kind != .constant { return error('AIR vector: scalar constant lane required') }
			extracted_scalar_constant(pools, pools.constants[lane.constant_index], element, bits, p.types[element].kind == .integer_t)!
		}
	} else if c.kind !in [.zero, .undef, .poison]! { return error('AIR vector: unsupported vector constant') }
	return count
}
// Keep the literal-only entry point for existing callers and qualification.
fn (p IRTypedProgram) constant_extract_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, op IRTypedInstruction, mixed bool, remaining int) !int {
	vector_operation_shape(p, op, 2)!
	source := p.operands[op.operands_start]
	element, _, _ := p.scalar_vector_type(source.type_index, mixed, remaining)!
	if op.result_type != element { return error('AIR vector: extract result type') }
	p.integer_bits(p.operands[op.operands_start + 1].type_index)!
	return p.constant_vector_profile(stream, pools, bodies, scope, source, mixed, remaining)!
}
fn extracted_scalar_value(pools IRConstantPools, c IRConstant, bits u32) !IntegerValue {
	if c.kind == .poison { return IntegerValue{poison: true} }
	if c.kind == .undef { return error('AIR vector: selected undef lane') }
	if c.kind == .zero { return IntegerValue{} }
	if c.kind !in [.integer, .floating]! { return error('AIR vector: scalar lane required') }
	return IntegerValue{value: pools.words[c.words_start] & constant_mask(bits)}
}
fn (m &IntegerMachine) extract_constant_lane(stream Stream, op IRTypedInstruction) !IntegerValue {
	index := m.read(op.operands_start + 1)!
	if index.poison { return IntegerValue{poison: true} }
	source := m.p.operands[op.operands_start]
	vector := m.p.types[source.type_index]
	if index.value >= vector.count { return IntegerValue{poison: true} }
	if source.number >= m.bodies.scopes[m.scope].base_id || m.pools.lookup(m.scope, source.number)!.kind == .argument {
		v := m.read_vector(stream, source)!
		if v.undef & (u16(1) << u32(index.value)) != 0 { return error('AIR vector: selected undef lane') }
		return v.lanes[int(index.value)]
	}
	c := m.p.extracted_constant(m.pools, m.bodies, m.scope, source)!
	bits := m.p.execution_bits(op.result_type, m.binary32)!
	if c.kind == .data { return IntegerValue{value: m.pools.words[c.words_start + int(index.value)] & constant_mask(bits)} }
	if c.kind == .aggregate {
		values := ir_values(stream, stream.records[c.record])
		lane := m.pools.lookup(c.scope, values[int(index.value)])!
		return extracted_scalar_value(m.pools, m.pools.constants[lane.constant_index], bits)!
	}
	return extracted_scalar_value(m.pools, c, bits)!
}
