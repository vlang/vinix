// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (mut b MemoryIndexBuilder) vector_bitcast_source(source IRTypedOperand, producer int, depth int) !MemoryIndexVectorSource {
	op := b.p.instructions[producer]
	b.p.vector_integer_bitcast_profile(b.stream, b.pools, b.bodies, b.scope, producer, op, 32)!
	_, bits, count := b.p.scalar_vector_type(source.type_index, false, 16)!
	operand := b.p.operands[op.operands_start]
	_, source_bits, source_count := b.p.scalar_vector_type(operand.type_index, false, 16)!
	key := memory_index_key(source.number, 3)
	if cached := b.cache[key] {
		node := b.nodes[cached]
		if node.height > max_memory_index_depth - depth { return error('AIR memory index: cached vector bitcast depth limit') }
		return MemoryIndexVectorSource{node: cached, base: node.right, height: node.height}
	}
	mut parents := [16]int{}
	for lane in 0 .. source_count {
		if b.nodes.len >= max_memory_index_nodes { return error('AIR memory index: bitcast selector node limit') }
		selector := b.nodes.len
		b.nodes << MemoryIndexNode{kind: .literal, bits: 32, value: u64(lane)}
		parents[lane] = b.project_vector_lane(operand, selector, producer, depth + 1)!
	}
	if source_count + count + 1 > max_memory_index_nodes - b.nodes.len { return error('AIR memory index: vector bitcast table limit') }
	inputs := b.nodes.len
	mut height := 1
	// Observe all source lanes before any result, including lanes discarded by
	// extraction/select. These existing scalar nodes give a contiguous table.
	for lane in 0 .. source_count {
		lane_height := b.nodes[parents[lane]].height + 1
		if lane_height > height { height = lane_height }
		b.nodes << MemoryIndexNode{kind: .projected_extract, bits: source_bits, left: parents[lane], height: lane_height}
	}
	height++
	if height > max_memory_index_depth - depth { return error('AIR memory index: vector bitcast graph depth') }
	base := b.nodes.len
	for lane in 0 .. count {
		b.nodes << MemoryIndexNode{kind: .projected_bitcast, bits: bits, source_bits: source_bits, left: inputs, value: u64(lane) * bits, height: height}
	}
	index := b.nodes.len
	b.nodes << MemoryIndexNode{kind: .vector_source, bits: bits, right: base, value: u64(count), height: height}
	b.cache[key] = index
	return MemoryIndexVectorSource{node: index, base: base, height: height}
}
