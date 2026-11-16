// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

struct MemoryIndexVectorSource {
	node     int
	base     int = -1
	argument int = -1
	undef    u64
	height   int = 1
	frozen   bool
}

// Only direct arguments/constants and earlier vector freezes are pure sources.
// Constant cache entries remain their original contiguous lane tables. Argument
// and freeze entries use POD metadata nodes in the same reserved vector tag.
fn (mut b MemoryIndexBuilder) frozen_vector_source(source IRTypedOperand, before int, depth int) !MemoryIndexVectorSource {
	if depth >= max_memory_index_depth { return error('AIR memory index: vector source depth limit') }
	element, bits, count := b.p.scalar_vector_type(source.type_index, true, 16)!
	b.p.integer_bits(element)!
	scope := b.bodies.scopes[b.scope]
	if source.number >= scope.base_id {
		slot := u64(source.number) - scope.base_id
		if slot >= u64(scope.results_count) || scope.results_start < 0 || scope.results_start > b.bodies.results.len || slot >= u64(b.bodies.results.len - scope.results_start) { return error('AIR memory index: vector result slot range') }
	}
	v := b.bodies.lookup(b.pools, b.scope, source.number)!
	mut producer := -1
	if v.kind == .instruction {
		producer = v.instruction
		if producer < scope.instructions_start || producer >= before || producer >= b.p.instructions.len || producer >= b.bodies.instructions.len || b.p.instructions[producer].result_type != source.type_index { return error('AIR memory index: earlier typed vector required') }
	} else if v.pooled.type_index != source.type_index { return error('AIR memory index: vector operand type') }
	if producer < 0 && v.pooled.kind == .constant {
		base := b.constant_lanes(source, bits, count)!
		return MemoryIndexVectorSource{node: base, base: base, undef: b.nodes[base].flags}
	}
	key := memory_index_key(source.number, 3)
	if cached := b.cache[key] {
		node := b.nodes[cached]
		if node.height > max_memory_index_depth - depth { return error('AIR memory index: cached vector depth limit') }
		return MemoryIndexVectorSource{node: cached, base: node.right, argument: node.argument, undef: node.flags, height: node.height, frozen: node.opcode == 1}
	}
	if b.nodes.len >= max_memory_index_nodes { return error('AIR memory index: vector source node limit') }
	mut node := MemoryIndexNode{kind: .vector_source, bits: bits, value: u64(count)}
	if producer < 0 {
		node = MemoryIndexNode{...node, argument: b.argument(source)!}
	} else {
		op := b.p.instructions[producer]
		inst := b.bodies.instructions[producer]
		if op.status != .decoded || inst.scope != b.scope || !inst.has_result || inst.next_value != source.number || inst.record < 0 || inst.record >= b.stream.records.len || b.stream.records[inst.record].code != 58 || op.is_volatile { return error('AIR memory index: vector freeze source required') }
		b.p.vector_freeze_profile(b.stream, b.pools, b.bodies, b.scope, producer, op, true, 16)!
		parent := b.frozen_vector_source(b.p.operands[op.operands_start], producer, depth + 1)!
		node = MemoryIndexNode{...node, opcode: 1, argument: parent.argument, left: parent.node, right: parent.base, flags: parent.undef, height: parent.height + 1}
	}
	if b.nodes.len >= max_memory_index_nodes || node.height > max_memory_index_depth - depth { return error('AIR memory index: vector source graph limit') }
	index := b.nodes.len
	b.nodes << node
	b.cache[key] = index
	return MemoryIndexVectorSource{node: index, base: node.right, argument: node.argument, undef: node.flags, height: node.height, frozen: node.opcode == 1}
}
