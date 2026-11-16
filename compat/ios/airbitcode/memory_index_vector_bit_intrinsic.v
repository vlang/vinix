// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (mut b MemoryIndexBuilder) vector_bit_intrinsic_source(source IRTypedOperand, producer int, depth int) !MemoryIndexVectorSource {
	if depth >= max_memory_index_depth { return error('AIR memory index: vector intrinsic depth limit') }
	op := b.p.instructions[producer]
	// The enclosing memory profile already bounds declaration attributes and
	// duplicate overload identities. Recheck the direct call and source here.
	b.p.vector_float_intrinsic_profile(b.ir, b.stream, b.pools, b.bodies, b.scope, producer, op, false, 32)!
	id, count, bits := vector_float_intrinsic_name(b.ir.functions[op.callee_function].name)!
	if id !in [.ctpop, .bitreverse, .bswap, .ctlz, .cttz] { return error('AIR memory index: unsupported vector intrinsic dependency') }
	// The immediate belongs to this call, even when its declaration or source
	// table has already been cached. Source freezing does not change the flag.
	zero_poison := if scalar_integer_zero_count(id) { b.p.vector_zero_count_flag(b.ir, b.pools, b.scope, op)! } else { u64(0) }
	key := memory_index_key(source.number, 3)
	if cached := b.cache[key] {
		node := b.nodes[cached]
		if node.height > max_memory_index_depth - depth { return error('AIR memory index: cached vector intrinsic depth limit') }
		return MemoryIndexVectorSource{node: cached, base: node.right, height: node.height}
	}
	mut parents := [16]int{}
	for lane in 0 .. count {
		if b.nodes.len >= max_memory_index_nodes { return error('AIR memory index: intrinsic selector node limit') }
		selector := b.nodes.len
		b.nodes << MemoryIndexNode{kind: .literal, bits: 32, value: u64(lane)}
		parents[lane] = b.project_vector_lane(b.p.operands[op.operands_start + 1], selector, producer, depth + 1)!
	}
	if count + 1 > max_memory_index_nodes - b.nodes.len { return error('AIR memory index: vector intrinsic table limit') }
	base := b.nodes.len
	mut height := 1
	for lane in 0 .. count {
		lane_height := b.nodes[parents[lane]].height + 1
		if lane_height > height { height = lane_height }
		b.nodes << MemoryIndexNode{kind: .projected_intrinsic, bits: bits, intrinsic: id, value: zero_poison, left: parents[lane], height: lane_height}
	}
	if height > max_memory_index_depth - depth { return error('AIR memory index: vector intrinsic graph depth') }
	index := b.nodes.len
	b.nodes << MemoryIndexNode{kind: .vector_source, bits: bits, right: base, value: u64(count), height: height}
	b.cache[key] = index
	return MemoryIndexVectorSource{node: index, base: base, height: height}
}
