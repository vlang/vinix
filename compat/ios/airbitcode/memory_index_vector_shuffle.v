// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Two POD words hold up to sixteen byte-sized mask entries. Values 0..31
// select a source lane; 255 represents poison or legacy undef. The original
// constant and every normalized entry are checked before packing either word.
fn (mut b MemoryIndexBuilder) project_vector_shuffle(source IRTypedOperand, selector int, producer int, depth int) !MemoryIndexNode {
	op := b.p.instructions[producer]
	b.p.vector_shuffle_profile(b.stream, b.pools, b.bodies, b.scope, producer, op, true, 64)!
	_, bits, count := b.p.scalar_vector_type(source.type_index, true, 16)!
	_, _, input_count := b.p.scalar_vector_type(op.source_type, true, 16)!
	mut first := u64(0)
	mut second := u64(0)
	for lane in 0 .. count {
		selected := b.p.indices[op.indices_start + lane]
		entry := if selected == ~u32(0) { u64(255) } else { u64(selected) }
		if lane < 8 { first |= entry << u32(lane * 8) }
		else { second |= entry << u32((lane - 8) * 8) }
	}
	if b.nodes.len > max_memory_index_nodes - 3 { return error('AIR memory index: shuffle node limit') }
	mapped := b.nodes.len
	b.nodes << MemoryIndexNode{kind: .shuffle_selector, bits: 32, left: selector, source_bits: u32(count), value: first, flags: second, height: b.nodes[selector].height + 1}
	rebased := b.nodes.len
	b.nodes << MemoryIndexNode{kind: .shuffle_lane, bits: 32, left: mapped, value: u64(input_count), height: b.nodes[mapped].height + 1}
	left := b.project_vector_lane(b.p.operands[op.operands_start], rebased, producer, depth + 1)!
	right := b.project_vector_lane(b.p.operands[op.operands_start + 1], rebased, producer, depth + 1)!
	mut height := b.nodes[left].height
	if b.nodes[right].height > height { height = b.nodes[right].height }
	return MemoryIndexNode{kind: .projected_shuffle, bits: bits, left: left, right: right, condition: mapped, value: u64(input_count), height: height + 1}
}
