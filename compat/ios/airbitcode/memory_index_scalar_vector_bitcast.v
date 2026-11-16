// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// A scalar source is already observed eagerly by its ordinary expression node.
// Keep one shared split table across extraction selectors.
fn (mut b MemoryIndexBuilder) split_bitcast_source(source IRTypedOperand, producer int, depth int) !MemoryIndexVectorSource {
	op := b.p.instructions[producer]
	b.p.scalar_vector_bitcast_profile(b.stream, b.pools, b.bodies, b.scope, producer, op, false, 32)!
	_, bits, count := b.p.scalar_vector_type(source.type_index, false, 16)!
	operand := b.p.operands[op.operands_start]
	source_bits := b.p.integer_bits(operand.type_index)!
	key := memory_index_key(source.number, 3)
	if cached := b.cache[key] {
		node := b.nodes[cached]
		if node.height > max_memory_index_depth - depth { return error('AIR memory index: cached scalar split depth limit') }
		return MemoryIndexVectorSource{node: cached, base: node.right, height: node.height}
	}
	parent := b.expression(operand, producer, depth + 1)!
	if count + 1 > max_memory_index_nodes - b.nodes.len { return error('AIR memory index: scalar split table limit') }
	height := b.nodes[parent].height + 1
	if height > max_memory_index_depth - depth { return error('AIR memory index: scalar split graph depth') }
	base := b.nodes.len
	for lane in 0 .. count {
		b.nodes << MemoryIndexNode{kind: .projected_bitcast, bits: bits, source_bits: source_bits, left: parent, value: u64(lane) * bits, height: height}
	}
	index := b.nodes.len
	b.nodes << MemoryIndexNode{kind: .vector_source, bits: bits, right: base, value: u64(count), height: height}
	b.cache[key] = index
	return MemoryIndexVectorSource{node: index, base: base, height: height}
}

// A scalar pack observes every source lane, including those discarded later.
// Contiguous scalar observations reuse the existing raw-bit evaluator.
fn (mut b MemoryIndexBuilder) packed_bitcast_node(op IRTypedInstruction, producer int, depth int) !MemoryIndexNode {
	b.p.scalar_vector_bitcast_profile(b.stream, b.pools, b.bodies, b.scope, producer, op, false, 32)!
	bits := b.p.integer_bits(op.result_type)!
	operand := b.p.operands[op.operands_start]
	_, source_bits, count := b.p.scalar_vector_type(operand.type_index, false, 16)!
	mut parents := [16]int{}
	for lane in 0 .. count {
		if b.nodes.len >= max_memory_index_nodes { return error('AIR memory index: scalar pack selector limit') }
		selector := b.nodes.len
		b.nodes << MemoryIndexNode{kind: .literal, bits: 32, value: u64(lane)}
		parents[lane] = b.project_vector_lane(operand, selector, producer, depth + 1)!
	}
	if count + 1 > max_memory_index_nodes - b.nodes.len { return error('AIR memory index: scalar pack input limit') }
	inputs := b.nodes.len
	mut height := 1
	for lane in 0 .. count {
		lane_height := b.nodes[parents[lane]].height + 1
		if lane_height > height { height = lane_height }
		b.nodes << MemoryIndexNode{kind: .projected_extract, bits: source_bits, left: parents[lane], height: lane_height}
	}
	height++
	if height > max_memory_index_depth - depth { return error('AIR memory index: scalar pack graph depth') }
	return MemoryIndexNode{kind: .projected_bitcast, bits: bits, source_bits: source_bits, left: inputs, height: height}
}
