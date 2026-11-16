// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const vector_subinsert_cache_base = vector_subvector_cache_base + 8976

fn vector_subinsert_name(name string) !(int, int, int) {
	if !name.starts_with('llvm.vector.insert.') { return error('AIR subinsert: canonical name required') }
	count, format, offset := subvector_token(name, 19)!
	if offset >= name.len || name[offset] != `.` { return error('AIR subinsert: source overload required') }
	source, source_format, end := subvector_token(name, offset + 1)!
	if end != name.len || source_format != format || source > count { return error('AIR subinsert: matching overloads required') }
	return count, source, format
}
fn vector_subinsert_key(count int, source int, format int) !int {
	if source < 1 || count < source || count > 16 || format < 0 || format > 65 { return error('AIR subinsert: cache shape') }
	return vector_subinsert_cache_base + format * 136 + count * (count - 1) / 2 + source - 1
}
// The immediate is call-local, even when the declaration has been cached.
fn (p IRTypedProgram) subinsert_offset(ir IRModule, pools IRConstantPools, scope int, op IRTypedInstruction, count int, source int) !int {
	operand := p.operands[op.operands_start + 3]; signature := ir.types[op.call_signature]
	if operand.type_index != ir.references[signature.refs_start + 3] || p.integer_bits(operand.type_index)! != 64 { return error('AIR subinsert: i64 offset required') }
	value := pools.lookup(scope, operand.number)!
	if value.kind != .constant { return error('AIR subinsert: constant offset required') }
	c := pools.constants[value.constant_index]
	if c.type_index != operand.type_index || c.splat || c.kind !in [.zero, .integer]! { return error('AIR subinsert: defined offset required') }
	offset := pools.scalar_bits(value.constant_index)!
	if offset > u64(count - source) || offset % u64(source) != 0 { return error('AIR subinsert: aligned in-range offset required') }
	return int(offset)
}
fn (p IRTypedProgram) vector_subinsert_profile(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !(int, int) {
	count, source_count, format := vector_subinsert_name(ir.functions[op.callee_function].name)!
	element, bits, actual := p.scalar_vector_type(op.result_type, mixed, remaining)!
	kind := p.types[element].kind
	if actual != count || (format < 64 && (kind != .integer_t || bits != u32(format + 1))) || (format == 64 && kind != .half_t) || (format == 65 && kind != .float_t) { return error('AIR subinsert: name/result identity') }
	signature := ir.types[op.call_signature]; mut work := count
	for i in 1..3 {
		argument := p.operands[op.operands_start + i]
		e, _, n := p.scalar_vector_type(argument.type_index, mixed, remaining - work)!
		if argument.type_index != ir.references[signature.refs_start + i] || e != element || n != if i == 1 { count } else { source_count } || (i == 1 && argument.type_index != op.result_type) { return error('AIR subinsert: source/result identity') }
		work += p.vector_source_profile(stream, pools, bodies, scope, index, argument, mixed, remaining - work)!
	}
	p.subinsert_offset(ir, pools, scope, op, count, source_count)!
	return work, vector_subinsert_key(count, source_count, format)!
}
fn inserted_subvector(base ScalarVectorValue, source ScalarVectorValue, count int, source_count int, offset int) !ScalarVectorValue {
	if source_count < 1 || count < source_count || count > 16 || offset < 0 || offset > count - source_count || offset % source_count != 0 { return error('AIR subinsert: insertion shape/offset') }
	mut result := ScalarVectorValue{}
	for lane in 0..count {
		inserted := lane >= offset && lane < offset + source_count
		selected := if inserted { lane - offset } else { lane }
		input := if inserted { source } else { base }; value := input.lanes[selected]
		if value.aggregate || value.vector { return error('AIR subinsert: scalar lanes required') }
		result.lanes[lane] = value
		if input.undef & (u16(1) << u32(selected)) != 0 { result.undef |= u16(1) << u32(lane) }
	}
	return result
}
fn (mut b MemoryIndexBuilder) project_subinsert(source IRTypedOperand, selector int, producer int, depth int) !MemoryIndexNode {
	op := b.p.instructions[producer]
	b.p.vector_float_intrinsic_profile(b.ir, b.stream, b.pools, b.bodies, b.scope, producer, op, false, 48)!
	count, source_count, _ := vector_subinsert_name(b.ir.functions[op.callee_function].name)!
	offset := b.p.subinsert_offset(b.ir, b.pools, b.scope, op, count, source_count)!
	_, bits, _ := b.p.scalar_vector_type(source.type_index, false, 16)!
	mut first := u64(0); mut second := u64(0)
	for lane in 0..count {
		entry := u64(if lane >= offset && lane < offset + source_count { count + lane - offset } else { lane })
		if lane < 8 { first |= entry << u32(lane * 8) } else { second |= entry << u32((lane - 8) * 8) }
	}
	if b.nodes.len > max_memory_index_nodes - 3 { return error('AIR memory index: subinsert selector limit') }
	mapped := b.nodes.len
	b.nodes << MemoryIndexNode{kind: .shuffle_selector, bits: 32, left: selector, source_bits: u32(count), value: first, flags: second, height: b.nodes[selector].height + 1}
	rebased := b.nodes.len
	b.nodes << MemoryIndexNode{kind: .shuffle_lane, bits: 32, left: mapped, value: u64(count), height: b.nodes[mapped].height + 1}
	left := b.project_vector_lane(b.p.operands[op.operands_start + 1], rebased, producer, depth + 1)!
	right := b.project_vector_lane(b.p.operands[op.operands_start + 2], rebased, producer, depth + 1)!
	height := 1 + if b.nodes[left].height > b.nodes[right].height { b.nodes[left].height } else { b.nodes[right].height }
	return MemoryIndexNode{kind: .projected_shuffle, bits: bits, left: left, right: right, condition: mapped, value: u64(count), height: height}
}
