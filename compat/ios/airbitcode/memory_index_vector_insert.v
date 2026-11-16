// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Project an insertion at the extraction selector. Literal undef replacements
// reuse the scalar poison leaf internally, but retain their separate tag here;
// no scalar consumer can obtain a deferred undef from the scalar cache.
fn (mut b MemoryIndexBuilder) project_vector_insert(source IRTypedOperand, selector int, producer int, depth int) !MemoryIndexNode {
	op := b.p.instructions[producer]
	b.p.vector_insert_profile(b.stream, b.pools, b.bodies, b.scope, producer, op, true, 16)!
	_, bits, count := b.p.scalar_vector_type(source.type_index, true, 16)!
	parent := b.project_vector_lane(b.p.operands[op.operands_start], selector, producer, depth + 1)!
	replacement := b.p.operands[op.operands_start + 1]
	mut undef := false
	if replacement.number < b.bodies.scopes[b.scope].base_id {
		v := b.pools.lookup(b.scope, replacement.number)!
		undef = v.kind == .constant && b.pools.constants[v.constant_index].kind == .undef
	}
	right := b.expression_source(replacement, producer, depth + 1, undef)!
	index := b.expression(b.p.operands[op.operands_start + 2], producer, depth + 1)!
	mut height := b.nodes[parent].height
	if b.nodes[right].height > height { height = b.nodes[right].height }
	if b.nodes[index].height > height { height = b.nodes[index].height }
	return MemoryIndexNode{kind: .projected_insert, bits: bits, left: parent, right: right, condition: index, lane: selector, value: u64(count), flags: u64(undef), height: height + 1}
}
