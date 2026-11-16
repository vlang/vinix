// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const vector_reverse_cache_base = vector_mulh_cache_base + 2048

// Element formats 0..63 are i1..i64; 64 and 65 are half and float.
fn vector_reverse_name(name string) !(int, int) {
	if !name.starts_with('llvm.vector.reverse.v') { return error('AIR vector reverse: canonical name required') }
	if name.ends_with('f16') || name.ends_with('f32') {
		count, bits := vector_float_overload(name, 21)!
		return count, if bits == 16 { 64 } else { 65 }
	}
	count, bits := vector_integer_overload(name, 21)!
	return count, int(bits) - 1
}
fn vector_reverse_key(count int, format int) !int {
	if count < 1 || count > 16 || format < 0 || format > 65 { return error('AIR vector reverse: cache shape') }
	return vector_reverse_cache_base + format * 16 + count - 1
}
// The enclosing intrinsic profile checks direct identity and call metadata.
fn (p IRTypedProgram) vector_reverse_profile(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !(int, int) {
	count, format := vector_reverse_name(ir.functions[op.callee_function].name)!
	element, bits, actual := p.scalar_vector_type(op.result_type, mixed, remaining)!
	kind := p.types[element].kind
	if actual != count || (format < 64 && (kind != .integer_t || bits != u32(format + 1))) || (format == 64 && kind != .half_t) || (format == 65 && kind != .float_t) { return error('AIR vector reverse: name/type identity') }
	signature := ir.types[op.call_signature]
	source := p.operands[op.operands_start + 1]
	if source.type_index != op.result_type || ir.references[signature.refs_start + 1] != op.result_type { return error('AIR vector reverse: matching source/result required') }
	work := count + p.vector_source_profile(stream, pools, bodies, scope, index, source, mixed, remaining - count)!
	return work, vector_reverse_key(count, format)!
}
fn reversed_vector(source ScalarVectorValue, count int) !ScalarVectorValue {
	if count < 1 || count > 16 { return error('AIR vector reverse: lane count') }
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		selected := count - 1 - lane; value := source.lanes[selected]
		if value.aggregate || value.vector { return error('AIR vector reverse: scalar lanes required') }
		result.lanes[lane] = value
		if source.undef & (u16(1) << u32(selected)) != 0 { result.undef |= u16(1) << u32(lane) }
	}
	return result
}
fn (mut b MemoryIndexBuilder) project_vector_reverse(source IRTypedOperand, selector int, producer int, depth int) !MemoryIndexNode {
	op := b.p.instructions[producer]
	b.p.vector_float_intrinsic_profile(b.ir, b.stream, b.pools, b.bodies, b.scope, producer, op, false, 32)!
	_, bits, count := b.p.scalar_vector_type(source.type_index, false, 16)!
	mut first := u64(0); mut second := u64(0)
	for lane in 0 .. count {
		entry := u64(count - 1 - lane)
		if lane < 8 { first |= entry << u32(lane * 8) } else { second |= entry << u32((lane - 8) * 8) }
	}
	if b.nodes.len >= max_memory_index_nodes { return error('AIR memory index: reverse selector node limit') }
	mapped := b.nodes.len
	b.nodes << MemoryIndexNode{kind: .shuffle_selector, bits: 32, left: selector, source_bits: u32(count), value: first, flags: second, height: b.nodes[selector].height + 1}
	parent := b.project_vector_lane(b.p.operands[op.operands_start + 1], mapped, producer, depth + 1)!
	// A single-source shuffle preserves deferred undef, including through a
	// later freeze, and poisons an invalid selector before choosing any lane.
	return MemoryIndexNode{kind: .projected_shuffle, bits: bits, left: parent, right: parent, condition: mapped, value: u64(count), height: b.nodes[parent].height + 1}
}
