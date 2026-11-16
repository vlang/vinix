// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const vector_splice_cache_base = vector_reverse_cache_base + 1056

fn vector_splice_name(name string) !(ScalarIntrinsic, int, int) {
	mut start := 0
	mut id := ScalarIntrinsic.vector_splice_left
	if name.starts_with('llvm.vector.splice.left.v') { start = 25 }
	else if name.starts_with('llvm.vector.splice.right.v') { start = 26; id = .vector_splice_right }
	else { return error('AIR vector splice: canonical name required') }
	if name.ends_with('f16') || name.ends_with('f32') {
		count, bits := vector_float_overload(name, start)!
		return id, count, if bits == 16 { 64 } else { 65 }
	}
	count, bits := vector_integer_overload(name, start)!
	return id, count, int(bits) - 1
}
fn vector_splice_key(id ScalarIntrinsic, count int, format int) !int {
	if id !in [.vector_splice_left, .vector_splice_right]! || count < 1 || count > 16 || format < 0 || format > 65 { return error('AIR vector splice: cache shape') }
	return vector_splice_cache_base + int(id == .vector_splice_right) * 1056 + format * 16 + count - 1
}
// Common call validation checks metadata, declaration identity and arity first.
fn (p IRTypedProgram) vector_splice_profile(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !(int, int) {
	id, count, format := vector_splice_name(ir.functions[op.callee_function].name)!
	element, bits, actual := p.scalar_vector_type(op.result_type, mixed, remaining)!
	kind := p.types[element].kind
	if actual != count || (format < 64 && (kind != .integer_t || bits != u32(format + 1))) || (format == 64 && kind != .half_t) || (format == 65 && kind != .float_t) { return error('AIR vector splice: name/type identity') }
	signature := ir.types[op.call_signature]
	mut work := count
	for i in 1 .. 3 {
		source := p.operands[op.operands_start + i]
		if source.type_index != op.result_type || ir.references[signature.refs_start + i] != op.result_type { return error('AIR vector splice: matching sources/result required') }
		work += p.vector_source_profile(stream, pools, bodies, scope, index, source, mixed, remaining - work)!
	}
	amount := p.operands[op.operands_start + 3]
	if amount.type_index != ir.references[signature.refs_start + 3] || p.integer_bits(amount.type_index)! != 32 { return error('AIR vector splice: scalar i32 offset required') }
	return work, vector_splice_key(id, count, format)!
}
fn spliced_vector(id ScalarIntrinsic, left ScalarVectorValue, right ScalarVectorValue, count int, offset IntegerValue) !ScalarVectorValue {
	if id !in [.vector_splice_left, .vector_splice_right]! || count < 1 || count > 16 || offset.aggregate || offset.vector { return error('AIR vector splice: family/count/offset') }
	mut result := ScalarVectorValue{}
	amount := offset.value & 0xffffffff
	if offset.poison || amount > u64(count) {
		for lane in 0 .. count { result.lanes[lane] = IntegerValue{poison: true} }
		return result
	}
	start := if id == .vector_splice_left { int(amount) } else { count - int(amount) }
	for lane in 0 .. count {
		selected := start + lane
		source := if selected < count { left } else { right }
		index := selected % count
		value := source.lanes[index]
		if value.aggregate || value.vector { return error('AIR vector splice: scalar lanes required') }
		result.lanes[lane] = value
		if source.undef & (u16(1) << u32(index)) != 0 { result.undef |= u16(1) << u32(lane) }
	}
	return result
}
fn (mut b MemoryIndexBuilder) project_vector_splice(source IRTypedOperand, selector int, producer int, depth int) !MemoryIndexNode {
	op := b.p.instructions[producer]
	b.p.vector_float_intrinsic_profile(b.ir, b.stream, b.pools, b.bodies, b.scope, producer, op, false, 48)!
	id, _, _ := vector_splice_name(b.ir.functions[op.callee_function].name)!
	_, bits, count := b.p.scalar_vector_type(source.type_index, false, 16)!
	amount := b.expression(b.p.operands[op.operands_start + 3], producer, depth + 1)!
	if b.nodes.len > max_memory_index_nodes - 3 { return error('AIR memory index: splice node limit') }
	mapped := b.nodes.len
	height := if b.nodes[selector].height > b.nodes[amount].height { b.nodes[selector].height } else { b.nodes[amount].height }
	b.nodes << MemoryIndexNode{kind: .splice_selector, bits: 32, left: selector, right: amount, source_bits: u32(count), opcode: u32(id == .vector_splice_right), height: height + 1}
	rebased := b.nodes.len
	b.nodes << MemoryIndexNode{kind: .shuffle_lane, bits: 32, left: mapped, value: u64(count), height: height + 2}
	left := b.project_vector_lane(b.p.operands[op.operands_start + 1], rebased, producer, depth + 1)!
	right := b.project_vector_lane(b.p.operands[op.operands_start + 2], rebased, producer, depth + 1)!
	parent_height := if b.nodes[left].height > b.nodes[right].height { b.nodes[left].height } else { b.nodes[right].height }
	return MemoryIndexNode{kind: .projected_shuffle, bits: bits, left: left, right: right, condition: mapped, value: u64(count), height: parent_height + 1}
}
