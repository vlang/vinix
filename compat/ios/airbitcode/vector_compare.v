// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (p IRTypedProgram) vector_compare_flag_mask(op IRTypedInstruction) u64 {
	if op.opcode < 32 || op.opcode > 41 || op.operands_count != 2 || op.operands_start < 0 || op.operands_start >= p.operands.len { return 0 }
	typ := p.operands[op.operands_start].type_index
	if typ < 0 || typ >= p.types.len { return 0 }
	t := p.types[typ]
	if t.kind != .vector_t || t.refs_count != 1 || t.refs_start < 0 || t.refs_start >= p.references.len { return 0 }
	element := p.references[t.refs_start]
	return if element >= 0 && element < p.types.len && p.types[element].kind == .integer_t { u64(1) } else { u64(0) }
}
fn (p IRTypedProgram) vector_compare_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !int {
	vector_operation_shape(p, IRTypedInstruction{...op, flags: 0, opcode: 0}, 2)!
	boolean, _, count := p.scalar_vector_type(op.result_type, false, remaining)!
	if p.integer_bits(boolean)! != 1 { return error('AIR vector: i1 comparison result required') }
	left := p.operands[op.operands_start]; right := p.operands[op.operands_start + 1]
	element, _, lanes := p.scalar_vector_type(left.type_index, mixed, 16)!
	if lanes != count || right.type_index != left.type_index { return error('AIR vector: comparison operand shape/type') }
	floating := p.types[element].kind in [.half_t, .float_t]!
	if (floating && op.opcode > 15) || (!floating && (op.opcode < 32 || op.opcode > 41)) || op.flags & ~p.vector_compare_flag_mask(op) != 0 { return error('AIR vector: comparison predicate/flags') }
	left_work := p.vector_source_profile(stream, pools, bodies, scope, index, left, mixed, remaining - count)!
	right_work := p.vector_source_profile(stream, pools, bodies, scope, index, right, mixed, remaining - count - left_work)!
	return count + left_work + right_work
}
fn compared_vector(left ScalarVectorValue, right ScalarVectorValue, element IRType, count int, predicate u32, flags u64) !ScalarVectorValue {
	if count < 1 || count > 16 { return error('AIR vector: comparison lane count') }
	floating := element.kind in [.half_t, .float_t]!
	if (floating && (predicate > 15 || flags != 0)) || (!floating && (element.kind != .integer_t || element.bits < 1 || element.bits > 64 || predicate < 32 || predicate > 41 || flags & ~u64(1) != 0)) { return error('AIR vector: comparison lane type/predicate/flags') }
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		// The constant FP predicates follow the existing scalar execution policy.
		if floating && predicate in [u32(0), 15]! { result.lanes[lane] = IntegerValue{value: u64(predicate == 15)}; continue }
		if (left.undef | right.undef) & (u16(1) << u32(lane)) != 0 { return error('AIR vector: undef comparison lane') }
		a := left.lanes[lane]; b := right.lanes[lane]
		if a.aggregate || a.vector || b.aggregate || b.vector { return error('AIR vector: scalar comparison lanes required') }
		result.lanes[lane] = if !floating { integer_compare_flags(predicate, flags, element.bits, a, b)! }
			else if a.poison || b.poison { IntegerValue{poison: true} }
			else if element.kind == .half_t { IntegerValue{value: u64(binary16_compare(predicate, u16(a.value), u16(b.value))!)} }
			else { IntegerValue{value: u64(binary32_compare(predicate, u32(a.value), u32(b.value))!)} }
	}
	return result
}
fn (mut m IntegerMachine) compare_vector_value(stream Stream, inst IRInstruction, op IRTypedInstruction) !IntegerValue {
	source := m.p.operands[op.operands_start]
	element, _, count := m.p.scalar_vector_type(source.type_index, m.binary32, 16)!
	typ := m.p.types[element]
	constant := typ.kind in [.half_t, .float_t]! && op.opcode in [u32(0), 15]!
	left := if constant { ScalarVectorValue{} } else { m.read_vector(stream, source)! }
	right := if constant { ScalarVectorValue{} } else { m.read_vector(stream, m.p.operands[op.operands_start + 1])! }
	return m.store_vector_value(inst, compared_vector(left, right, typ, count, op.opcode, op.flags)!)!
}
