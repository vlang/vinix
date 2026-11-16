// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const vector_active_mask_cache_base = vector_step_cache_base + 912

fn vector_active_mask_name(name string) !(int, u32) {
	if !name.starts_with('llvm.get.active.lane.mask.v') { return error('AIR active mask: canonical name required') }
	mut offset := 27
	if offset >= name.len || name[offset] == `0` { return error('AIR active mask: canonical count required') }
	mut count := 0
	for offset < name.len && name[offset] >= `0` && name[offset] <= `9` {
		count = count * 10 + int(name[offset] - `0`); offset++
		if count > 16 { return error('AIR active mask: lane count') }
	}
	if count < 1 || offset + 5 > name.len || name[offset] != `i` || name[offset + 1] != `1` || name[offset + 2] != `.` || name[offset + 3] != `i` { return error('AIR active mask: i1 result required') }
	offset += 4
	if name[offset] == `0` { return error('AIR active mask: canonical width required') }
	mut width := u32(0)
	for offset < name.len {
		if name[offset] < `0` || name[offset] > `9` { return error('AIR active mask: integer width required') }
		width = width * 10 + u32(name[offset] - `0`); offset++
		if width > 64 { return error('AIR active mask: integer width') }
	}
	vector_active_mask_key(count, width)!
	return count, width
}
fn vector_active_mask_key(count int, width u32) !int {
	if count < 1 || count > 16 || width < 1 || width > 64 { return error('AIR active mask: cache shape') }
	return vector_active_mask_cache_base + int(width - 1) * 16 + count - 1
}
// Common validation checks direct identity, attributes, metadata and arity.
fn (p IRTypedProgram) vector_active_mask_profile(ir IRModule, op IRTypedInstruction, remaining int) !(int, int) {
	count, width := vector_active_mask_name(ir.functions[op.callee_function].name)!
	_, bits, actual := p.scalar_vector_type(op.result_type, false, remaining)!
	if bits != 1 || actual != count { return error('AIR active mask: name/result identity') }
	signature := ir.types[op.call_signature]
	a := p.operands[op.operands_start + 1]; b := p.operands[op.operands_start + 2]
	if a.type_index != b.type_index || a.type_index != ir.references[signature.refs_start + 1] || b.type_index != ir.references[signature.refs_start + 2] || p.integer_bits(a.type_index)! != width { return error('AIR active mask: matching scalar argument types required') }
	return count, vector_active_mask_key(count, width)!
}
fn active_mask_vector(base IntegerValue, limit IntegerValue, count int, width u32) !ScalarVectorValue {
	vector_active_mask_key(count, width)!
	if base.aggregate || base.vector || limit.aggregate || limit.vector { return error('AIR active mask: scalar arguments required') }
	mut result := ScalarVectorValue{}
	a := base.value & constant_mask(width); b := limit.value & constant_mask(width)
	for lane in 0 .. count {
		// Mathematical base + lane < limit, including widths too narrow to
		// enumerate the vector. No addition or narrowing of lane can wrap.
		result.lanes[lane] = if base.poison || limit.poison { IntegerValue{poison: true} } else { IntegerValue{value: u64(a < b && u64(lane) < b - a)} }
	}
	return result
}
fn (mut b MemoryIndexBuilder) project_active_mask(selector int, producer int, depth int) !MemoryIndexNode {
	op := b.p.instructions[producer]
	b.p.vector_float_intrinsic_profile(b.ir, b.stream, b.pools, b.bodies, b.scope, producer, op, false, 16)!
	count, _ := vector_active_mask_name(b.ir.functions[op.callee_function].name)!
	base := b.expression(b.p.operands[op.operands_start + 1], producer, depth + 1)!
	limit := b.expression(b.p.operands[op.operands_start + 2], producer, depth + 1)!
	if b.nodes.len > max_memory_index_nodes - 5 { return error('AIR memory index: active mask node limit') }
	mut first := u64(0); mut second := u64(0)
	for lane in 0 .. count {
		if lane < 8 { first |= u64(lane) << u32(lane * 8) } else { second |= u64(lane) << u32((lane - 8) * 8) }
	}
	// Use existing scalar nodes. Inputs are already normalized to their type;
	// computing distance at i64 preserves even tiny argument widths.
	mapped := b.nodes.len
	b.nodes << MemoryIndexNode{kind: .shuffle_selector, bits: 64, left: selector, source_bits: u32(count), value: first, flags: second, height: b.nodes[selector].height + 1}
	height := 1 + if b.nodes[base].height > b.nodes[limit].height { b.nodes[base].height } else { b.nodes[limit].height }
	distance := b.nodes.len
	b.nodes << MemoryIndexNode{kind: .binary, bits: 64, opcode: 1, left: limit, right: base, height: height}
	ordered := b.nodes.len
	b.nodes << MemoryIndexNode{kind: .compare, bits: 1, source_bits: 64, opcode: 36, left: base, right: limit, height: height}
	within := b.nodes.len
	comparison_height := 1 + if b.nodes[mapped].height > height { b.nodes[mapped].height } else { height }
	b.nodes << MemoryIndexNode{kind: .compare, bits: 1, source_bits: 64, opcode: 36, left: mapped, right: distance, height: comparison_height}
	return MemoryIndexNode{kind: .binary, bits: 1, opcode: 10, left: ordered, right: within, height: comparison_height + 1}
}
