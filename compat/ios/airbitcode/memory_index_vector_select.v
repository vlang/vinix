// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (b MemoryIndexBuilder) vector_index_producer(source IRTypedOperand, before int) !int {
	scope := b.bodies.scopes[b.scope]
	if source.number >= scope.base_id {
		slot := u64(source.number) - scope.base_id
		if slot >= u64(scope.results_count) || scope.results_start < 0 || scope.results_start > b.bodies.results.len || slot >= u64(b.bodies.results.len - scope.results_start) { return error('AIR memory index: vector result slot range') }
	}
	v := b.bodies.lookup(b.pools, b.scope, source.number)!
	if v.kind == .instruction {
		producer := v.instruction
		if producer < scope.instructions_start || producer >= before || producer >= b.p.instructions.len || producer >= b.bodies.instructions.len || b.p.instructions[producer].result_type != source.type_index { return error('AIR memory index: earlier typed vector required') }
		return producer
	}
	if v.pooled.type_index != source.type_index { return error('AIR memory index: vector operand type') }
	return -1
}

// Keep the established freeze-only representation and costs when no other
// supported vector operation occurs in the source chain.
fn (b MemoryIndexBuilder) vector_projection_source(source IRTypedOperand, before int, depth int) !bool {
	if depth >= max_memory_index_depth { return error('AIR memory index: vector source depth limit') }
	producer := b.vector_index_producer(source, before)!
	if producer < 0 { return false }
	inst := b.bodies.instructions[producer]
	if inst.record < 0 || inst.record >= b.stream.records.len { return error('AIR memory index: vector source record') }
	code := b.stream.records[inst.record].code
	if code in [u64(2), 3, 5, 7, 8, 29] { return true }
	if code != 58 { return false }
	op := b.p.instructions[producer]
	b.p.vector_freeze_profile(b.stream, b.pools, b.bodies, b.scope, producer, op, true, 16)!
	return b.vector_projection_source(b.p.operands[op.operands_start], producer, depth + 1)!
}

// Scalar lane projections keep undef deferred until the final extraction.
// This permits a vector select to discard an unchosen undef lane, and a source
// freeze to repair it. Scalar consumers never receive the deferred tag.
fn (mut b MemoryIndexBuilder) project_vector_lane(source IRTypedOperand, selector int, before int, depth int) !int {
	if depth >= max_memory_index_depth || selector < 0 || selector >= b.nodes.len { return error('AIR memory index: projection selector/depth') }
	element, bits, count := b.p.scalar_vector_type(source.type_index, true, 16)!
	b.p.integer_bits(element)!
	producer := b.vector_index_producer(source, before)!
	// Tags 4..259 identify a projection by its scalar selector node (0..255).
	key := memory_index_key(source.number, u64(selector) + 4)
	if cached := b.cache[key] {
		if b.nodes[cached].height > max_memory_index_depth - depth { return error('AIR memory index: cached projection depth limit') }
		return cached
	}
	if b.nodes.len >= max_memory_index_nodes { return error('AIR memory index: projection node limit') }
	mut node := MemoryIndexNode{bits: bits}
	if producer < 0 {
		if b.pools.lookup(b.scope, source.number)!.kind == .constant {
			base := b.constant_lanes(source, bits, count)!
			node = MemoryIndexNode{kind: .constant_lane, bits: bits, opcode: 2, left: selector, right: base, value: u64(count), flags: b.nodes[base].flags, height: 1 + b.nodes[selector].height}
		} else {
			node = MemoryIndexNode{kind: .dynamic_lane, bits: bits, argument: b.argument(source)!, left: selector, value: u64(count), height: 1 + b.nodes[selector].height}
		}
	} else {
		op := b.p.instructions[producer]
		inst := b.bodies.instructions[producer]
		if op.status != .decoded || inst.scope != b.scope || !inst.has_result || inst.next_value != source.number || inst.record < 0 || inst.record >= b.stream.records.len || op.is_volatile { return error('AIR memory index: decoded vector projection required') }
		code := b.stream.records[inst.record].code
		if code == 58 && !b.vector_projection_source(source, before, depth)! {
			vector := b.frozen_vector_source(source, before, depth)!
			node = MemoryIndexNode{kind: if vector.base >= 0 { MemoryIndexKind.constant_lane } else { MemoryIndexKind.dynamic_lane }, bits: bits, opcode: 2 | u32(vector.frozen), argument: vector.argument, left: selector, right: vector.base, condition: vector.node, value: u64(count), flags: vector.undef, height: 1 + if vector.height > b.nodes[selector].height { vector.height } else { b.nodes[selector].height }}
		} else if code == 58 {
			b.p.vector_freeze_profile(b.stream, b.pools, b.bodies, b.scope, producer, op, true, 16)!
			parent := b.project_vector_lane(b.p.operands[op.operands_start], selector, producer, depth + 1)!
			node = MemoryIndexNode{kind: .projected_freeze, bits: bits, left: parent, right: selector, value: u64(count), height: 1 + b.nodes[parent].height}
		} else if code in [u64(5), 29] {
			vector_operation_shape(b.p, op, 3)!
			condition := b.p.operands[op.operands_start + 2]
			if b.p.integer_bits(condition.type_index)! != 1 { return error('AIR memory index: scalar vector-select condition required') }
			b.p.vector_select_profile(b.stream, b.pools, b.bodies, b.scope, producer, op, true, 64)!
			left := b.project_vector_lane(b.p.operands[op.operands_start], selector, producer, depth + 1)!
			right := b.project_vector_lane(b.p.operands[op.operands_start + 1], selector, producer, depth + 1)!
			cond := b.expression(condition, producer, depth + 1)!
			mut height := b.nodes[left].height
			if b.nodes[right].height > height { height = b.nodes[right].height }
			if b.nodes[cond].height > height { height = b.nodes[cond].height }
			node = MemoryIndexNode{kind: .projected_select, bits: bits, left: left, right: right, condition: cond, height: height + 1}
		} else if code == 7 {
			node = b.project_vector_insert(source, selector, producer, depth)!
		} else if code == 8 {
			node = b.project_vector_shuffle(source, selector, producer, depth)!
		} else if code == 2 {
			table := b.vector_binary_source(source, producer, depth + 1)!
			node = MemoryIndexNode{kind: .constant_lane, bits: bits, left: selector, right: table.base, condition: table.node, value: u64(count), height: 1 + if table.height > b.nodes[selector].height { table.height } else { b.nodes[selector].height }}
		} else if code == 3 {
			table := b.vector_cast_source(source, producer, depth + 1)!
			node = MemoryIndexNode{kind: .constant_lane, bits: bits, left: selector, right: table.base, condition: table.node, value: u64(count), height: 1 + if table.height > b.nodes[selector].height { table.height } else { b.nodes[selector].height }}
		} else { return error('AIR memory index: unsupported vector projection dependency') }
	}
	if b.nodes.len >= max_memory_index_nodes || node.height > max_memory_index_depth - depth { return error('AIR memory index: projection graph limit') }
	index := b.nodes.len
	b.nodes << node
	b.cache[key] = index
	return index
}
