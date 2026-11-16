// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Every mask lane must be defined even if extraction or a later select ignores
// it. Keep this guarded table separate from ordinary/frozen source snapshots.
fn (mut b MemoryIndexBuilder) vector_condition_source(source IRTypedOperand, before int, depth int) !MemoryIndexVectorSource {
	if depth >= max_memory_index_depth { return error('AIR memory index: vector condition depth limit') }
	element, _, count := b.p.scalar_vector_type(source.type_index, false, 16)!
	if b.p.integer_bits(element)! != 1 { return error('AIR memory index: i1 vector condition required') }
	b.p.vector_source_profile(b.stream, b.pools, b.bodies, b.scope, before, source, false, 16)!
	key := memory_index_key(source.number, 260)
	if cached := b.cache[key] {
		node := b.nodes[cached]
		if node.height > max_memory_index_depth - depth { return error('AIR memory index: cached vector condition depth limit') }
		return MemoryIndexVectorSource{node: cached, base: node.right, height: node.height}
	}
	mut parents := [16]int{}
	for lane in 0 .. count {
		if b.nodes.len >= max_memory_index_nodes { return error('AIR memory index: condition selector node limit') }
		selector := b.nodes.len
		b.nodes << MemoryIndexNode{kind: .literal, bits: 32, value: u64(lane)}
		parents[lane] = b.project_vector_lane(source, selector, before, depth + 1)!
	}
	if count + 1 > max_memory_index_nodes - b.nodes.len { return error('AIR memory index: vector condition table limit') }
	base := b.nodes.len
	mut height := 1
	for lane in 0 .. count {
		lane_height := b.nodes[parents[lane]].height + 1
		if lane_height > height { height = lane_height }
		// The extraction guard rejects deferred undef and preserves poison.
		b.nodes << MemoryIndexNode{kind: .projected_extract, bits: 1, left: parents[lane], height: lane_height}
	}
	if height > max_memory_index_depth - depth { return error('AIR memory index: vector condition graph depth') }
	index := b.nodes.len
	b.nodes << MemoryIndexNode{kind: .vector_source, bits: 1, right: base, value: u64(count), height: height}
	b.cache[key] = index
	return MemoryIndexVectorSource{node: index, base: base, height: height}
}
