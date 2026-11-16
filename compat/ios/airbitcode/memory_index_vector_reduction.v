// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Every lane is observed before the scalar result becomes available. Keep the
// observations contiguous for the fixed-size evaluator, including undef lanes
// that an eventual scalar select or freeze would otherwise discard.
fn (mut b MemoryIndexBuilder) reduction_node(op IRTypedInstruction, producer int, depth int) !MemoryIndexNode {
	// The enclosing memory profile also checks attributes and duplicate identities.
	b.p.vector_reduction_profile(b.ir, b.stream, b.pools, b.bodies, b.scope, producer, op, 17)!
	id, count, bits := vector_reduction_name(b.ir.functions[op.callee_function].name)!
	source := b.p.operands[op.operands_start + 1]
	mut parents := [16]int{}
	for lane in 0 .. count {
		if b.nodes.len >= max_memory_index_nodes { return error('AIR memory index: reduction selector limit') }
		selector := b.nodes.len
		b.nodes << MemoryIndexNode{kind: .literal, bits: 32, value: u64(lane)}
		parents[lane] = b.project_vector_lane(source, selector, producer, depth + 1)!
	}
	if count + 1 > max_memory_index_nodes - b.nodes.len { return error('AIR memory index: reduction input limit') }
	inputs := b.nodes.len
	mut height := 1
	for lane in 0 .. count {
		lane_height := b.nodes[parents[lane]].height + 1
		if lane_height > height { height = lane_height }
		b.nodes << MemoryIndexNode{kind: .projected_extract, bits: bits, left: parents[lane], height: lane_height}
	}
	height++
	if height > max_memory_index_depth - depth { return error('AIR memory index: reduction graph depth') }
	return MemoryIndexNode{kind: .integer_reduction, bits: bits, opcode: u32(id), left: inputs, value: u64(count), height: height}
}
