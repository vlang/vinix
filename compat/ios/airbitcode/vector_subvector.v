// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const vector_subvector_cache_base = vector_active_mask_cache_base + 1024

// Canonical fixed-vector token, returning its next unconsumed byte. Both
// overloads must be read without allocating substrings on execution paths.
fn subvector_token(name string, start int) !(int, int, int) {
	if start >= name.len || name[start] != `v` { return error('AIR subvector: fixed vector token required') }
	mut offset := start + 1
	if offset >= name.len || name[offset] == `0` { return error('AIR subvector: canonical count required') }
	mut count := 0
	for offset < name.len && name[offset] >= `0` && name[offset] <= `9` {
		count = count * 10 + int(name[offset] - `0`); offset++
		if count > 16 { return error('AIR subvector: lane count') }
	}
	if count < 1 || offset >= name.len || name[offset] !in [`i`, `f`] { return error('AIR subvector: element format') }
	floating := name[offset] == `f`; offset++
	if offset >= name.len || name[offset] == `0` { return error('AIR subvector: canonical width required') }
	mut width := 0
	for offset < name.len && name[offset] >= `0` && name[offset] <= `9` {
		width = width * 10 + int(name[offset] - `0`); offset++
		if width > 64 { return error('AIR subvector: element width') }
	}
	if width < 1 || (floating && width !in [16, 32]) { return error('AIR subvector: supported element width required') }
	return count, if floating { if width == 16 { 64 } else { 65 } } else { width - 1 }, offset
}
fn vector_subvector_name(name string) !(int, int, int) {
	if !name.starts_with('llvm.vector.extract.') { return error('AIR subvector: canonical name required') }
	count, format, offset := subvector_token(name, 20)!
	if offset >= name.len || name[offset] != `.` { return error('AIR subvector: source overload required') }
	source, source_format, end := subvector_token(name, offset + 1)!
	if end != name.len || source_format != format || source < count { return error('AIR subvector: matching overloads required') }
	return count, source, format
}
fn vector_subvector_key(count int, source int, format int) !int {
	if count < 1 || source < count || source > 16 || format < 0 || format > 65 { return error('AIR subvector: cache shape') }
	return vector_subvector_cache_base + format * 136 + source * (source - 1) / 2 + count - 1
}
// Validate every call-local immediate even on declaration/cache hits.
fn (p IRTypedProgram) subvector_offset(ir IRModule, pools IRConstantPools, scope int, op IRTypedInstruction, count int, source int) !int {
	operand := p.operands[op.operands_start + 2]; signature := ir.types[op.call_signature]
	if operand.type_index != ir.references[signature.refs_start + 2] || p.integer_bits(operand.type_index)! != 64 { return error('AIR subvector: i64 offset required') }
	value := pools.lookup(scope, operand.number)!
	if value.kind != .constant { return error('AIR subvector: constant offset required') }
	c := pools.constants[value.constant_index]
	if c.type_index != operand.type_index || c.splat || c.kind !in [.zero, .integer]! { return error('AIR subvector: defined offset required') }
	offset := pools.scalar_bits(value.constant_index)!
	if offset > u64(source - count) || offset % u64(count) != 0 { return error('AIR subvector: aligned in-range offset required') }
	return int(offset)
}
fn (p IRTypedProgram) vector_subvector_profile(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !(int, int) {
	count, source_count, format := vector_subvector_name(ir.functions[op.callee_function].name)!
	element, bits, actual := p.scalar_vector_type(op.result_type, mixed, remaining)!
	kind := p.types[element].kind
	if actual != count || (format < 64 && (kind != .integer_t || bits != u32(format + 1))) || (format == 64 && kind != .half_t) || (format == 65 && kind != .float_t) { return error('AIR subvector: name/result identity') }
	argument := p.operands[op.operands_start + 1]; signature := ir.types[op.call_signature]
	e, _, n := p.scalar_vector_type(argument.type_index, mixed, remaining - count)!
	if argument.type_index != ir.references[signature.refs_start + 1] || e != element || n != source_count { return error('AIR subvector: name/source identity') }
	p.subvector_offset(ir, pools, scope, op, count, source_count)!
	return count + p.vector_source_profile(stream, pools, bodies, scope, index, argument, mixed, remaining - count)!, vector_subvector_key(count, source_count, format)!
}
fn extracted_subvector(source ScalarVectorValue, count int, source_count int, offset int) !ScalarVectorValue {
	if count < 1 || source_count < count || source_count > 16 || offset < 0 || offset > source_count - count || offset % count != 0 { return error('AIR subvector: extraction shape/offset') }
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		selected := offset + lane; value := source.lanes[selected]
		if value.aggregate || value.vector { return error('AIR subvector: scalar lanes required') }
		result.lanes[lane] = value
		if source.undef & (u16(1) << u32(selected)) != 0 { result.undef |= u16(1) << u32(lane) }
	}
	return result
}
fn (mut b MemoryIndexBuilder) project_subvector(source IRTypedOperand, selector int, producer int, depth int) !MemoryIndexNode {
	op := b.p.instructions[producer]
	b.p.vector_float_intrinsic_profile(b.ir, b.stream, b.pools, b.bodies, b.scope, producer, op, false, 32)!
	count, source_count, _ := vector_subvector_name(b.ir.functions[op.callee_function].name)!
	offset := b.p.subvector_offset(b.ir, b.pools, b.scope, op, count, source_count)!
	_, bits, _ := b.p.scalar_vector_type(source.type_index, false, 16)!
	mut first := u64(0); mut second := u64(0)
	for lane in 0 .. count {
		entry := u64(offset + lane)
		if lane < 8 { first |= entry << u32(lane * 8) } else { second |= entry << u32((lane - 8) * 8) }
	}
	if b.nodes.len >= max_memory_index_nodes { return error('AIR memory index: subvector selector limit') }
	mapped := b.nodes.len
	b.nodes << MemoryIndexNode{kind: .shuffle_selector, bits: 32, left: selector, source_bits: u32(count), value: first, flags: second, height: b.nodes[selector].height + 1}
	parent := b.project_vector_lane(b.p.operands[op.operands_start + 1], mapped, producer, depth + 1)!
	return MemoryIndexNode{kind: .projected_shuffle, bits: bits, left: parent, right: parent, condition: mapped, value: u64(source_count), height: b.nodes[parent].height + 1}
}
