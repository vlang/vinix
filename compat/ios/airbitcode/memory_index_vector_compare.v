// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Comparisons observe both complete operands before extraction. Keep poison
// lane-local and reject undef eagerly, as in ordinary vector execution.
fn (mut b MemoryIndexBuilder) vector_compare_source(source IRTypedOperand, producer int, depth int) !MemoryIndexVectorSource {
	if depth >= max_memory_index_depth { return error('AIR memory index: vector comparison depth limit') }
	op := b.p.instructions[producer]
	b.p.vector_compare_profile(b.stream, b.pools, b.bodies, b.scope, producer, op, false, 48)!
	_, bits, count := b.p.scalar_vector_type(source.type_index, false, 16)!
	_, source_bits, _ := b.p.scalar_vector_type(b.p.operands[op.operands_start].type_index, false, 16)!
	key := memory_index_key(source.number, 3)
	if cached := b.cache[key] {
		node := b.nodes[cached]
		if node.height > max_memory_index_depth - depth { return error('AIR memory index: cached vector comparison depth limit') }
		return MemoryIndexVectorSource{node: cached, base: node.right, height: node.height}
	}
	mut left := [16]int{}
	mut right := [16]int{}
	for lane in 0 .. count {
		if b.nodes.len >= max_memory_index_nodes { return error('AIR memory index: comparison selector node limit') }
		selector := b.nodes.len
		b.nodes << MemoryIndexNode{kind: .literal, bits: 32, value: u64(lane)}
		left[lane] = b.project_vector_lane(b.p.operands[op.operands_start], selector, producer, depth + 1)!
		right[lane] = b.project_vector_lane(b.p.operands[op.operands_start + 1], selector, producer, depth + 1)!
	}
	if count + 1 > max_memory_index_nodes - b.nodes.len { return error('AIR memory index: vector comparison table limit') }
	base := b.nodes.len
	mut height := 1
	for lane in 0 .. count {
		lane_height := 1 + if b.nodes[left[lane]].height > b.nodes[right[lane]].height { b.nodes[left[lane]].height } else { b.nodes[right[lane]].height }
		if lane_height > height { height = lane_height }
		b.nodes << MemoryIndexNode{kind: .projected_compare, bits: bits, source_bits: source_bits, opcode: op.opcode, flags: op.flags, left: left[lane], right: right[lane], height: lane_height}
	}
	if height > max_memory_index_depth - depth { return error('AIR memory index: vector comparison graph depth') }
	index := b.nodes.len
	b.nodes << MemoryIndexNode{kind: .vector_source, bits: bits, right: base, value: u64(count), height: height}
	b.cache[key] = index
	return MemoryIndexVectorSource{node: index, base: base, height: height}
}
