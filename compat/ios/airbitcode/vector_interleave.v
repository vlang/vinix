// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const vector_interleave_cache_base = vector_splice_cache_base + 2112

fn vector_interleave_intrinsic(id ScalarIntrinsic) bool {
	return int(id) >= int(ScalarIntrinsic.vector_interleave2) && int(id) <= int(ScalarIntrinsic.vector_interleave8)
}
fn vector_interleave_name(name string) !(ScalarIntrinsic, int, int) {
	if !name.starts_with('llvm.vector.interleave') || name.len < 26 || name[22] < `2` || name[22] > `8` || name[23] != `.` || name[24] != `v` { return error('AIR vector interleave: canonical name required') }
	factor := int(name[22] - `0`)
	id := match factor { 2 { ScalarIntrinsic.vector_interleave2 } 3 { .vector_interleave3 } 4 { .vector_interleave4 } 5 { .vector_interleave5 } 6 { .vector_interleave6 } 7 { .vector_interleave7 } else { .vector_interleave8 } }
	mut count := 0; mut format := 0
	if name.ends_with('f16') || name.ends_with('f32') {
		n, bits := vector_float_overload(name, 25)!; count = n; format = if bits == 16 { 64 } else { 65 }
	} else {
		n, bits := vector_integer_overload(name, 25)!; count = n; format = int(bits) - 1
	}
	if count % factor != 0 { return error('AIR vector interleave: result must contain complete input groups') }
	return id, count, format
}
fn vector_interleave_key(id ScalarIntrinsic, count int, format int) !int {
	if !vector_interleave_intrinsic(id) || count < 1 || count > 16 || format < 0 || format > 65 { return error('AIR vector interleave: cache shape') }
	factor := scalar_intrinsic_arity(id)
	if count % factor != 0 { return error('AIR vector interleave: cache lane multiple') }
	mut offset := 0
	for n in 2 .. factor { offset += 16 / n }
	return vector_interleave_cache_base + format * 26 + offset + count / factor - 1
}
// The common call profile checks exact declaration identity and call metadata.
fn (p IRTypedProgram) vector_interleave_profile(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !(int, int) {
	id, count, format := vector_interleave_name(ir.functions[op.callee_function].name)!
	element, bits, actual := p.scalar_vector_type(op.result_type, mixed, remaining)!
	kind := p.types[element].kind
	if actual != count || (format < 64 && (kind != .integer_t || bits != u32(format + 1))) || (format == 64 && kind != .half_t) || (format == 65 && kind != .float_t) { return error('AIR vector interleave: name/type identity') }
	factor := scalar_intrinsic_arity(id); signature := ir.types[op.call_signature]
	mut work := count
	mut source_type := -1
	for i in 0 .. factor {
		source := p.operands[op.operands_start + i + 1]
		if source.type_index != ir.references[signature.refs_start + i + 1] || (source_type >= 0 && source.type_index != source_type) { return error('AIR vector interleave: matching input types required') }
		e, _, lanes := p.scalar_vector_type(source.type_index, mixed, remaining - work)!
		if e != element || lanes != count / factor { return error('AIR vector interleave: input/result shape') }
		work += p.vector_source_profile(stream, pools, bodies, scope, index, source, mixed, remaining - work)!
		source_type = source.type_index
	}
	return work, vector_interleave_key(id, count, format)!
}
fn interleaved_vector(sources [8]ScalarVectorValue, factor int, input_count int) !ScalarVectorValue {
	if factor < 2 || factor > 8 || input_count < 1 || input_count > 16 / factor { return error('AIR vector interleave: factor/count') }
	mut result := ScalarVectorValue{}
	for lane in 0 .. factor * input_count {
		input := lane % factor; index := lane / factor
		value := sources[input].lanes[index]
		if value.aggregate || value.vector { return error('AIR vector interleave: scalar lanes required') }
		result.lanes[lane] = value
		if sources[input].undef & (u16(1) << u32(index)) != 0 { result.undef |= u16(1) << u32(lane) }
	}
	return result
}
fn (mut b MemoryIndexBuilder) project_vector_interleave(source IRTypedOperand, selector int, producer int, depth int) !MemoryIndexNode {
	op := b.p.instructions[producer]
	b.p.vector_float_intrinsic_profile(b.ir, b.stream, b.pools, b.bodies, b.scope, producer, op, false, 32)!
	id, count, _ := vector_interleave_name(b.ir.functions[op.callee_function].name)!
	_, bits, _ := b.p.scalar_vector_type(source.type_index, false, 16)!
	factor := scalar_intrinsic_arity(id); input_count := count / factor
	mut first := u64(0); mut second := u64(0)
	for lane in 0 .. count {
		entry := u64((lane % factor) * input_count + lane / factor)
		if lane < 8 { first |= entry << u32(lane * 8) } else { second |= entry << u32((lane - 8) * 8) }
	}
	if b.nodes.len > max_memory_index_nodes - 3 { return error('AIR memory index: interleave selector limit') }
	mapped := b.nodes.len
	b.nodes << MemoryIndexNode{kind: .shuffle_selector, bits: 32, left: selector, source_bits: u32(count), value: first, flags: second, height: b.nodes[selector].height + 1}
	rebased := b.nodes.len
	b.nodes << MemoryIndexNode{kind: .shuffle_lane, bits: 32, left: mapped, value: u64(input_count), height: b.nodes[mapped].height + 1}
	mut parents := [8]int{}
	for i in 0 .. factor { parents[i] = b.project_vector_lane(b.p.operands[op.operands_start + i + 1], rebased, producer, depth + 1)! }
	mut parent := parents[0]
	for i in 1 .. factor {
		right := parents[i]
		height := 1 + if b.nodes[parent].height > b.nodes[right].height { b.nodes[parent].height } else { b.nodes[right].height }
		node := MemoryIndexNode{kind: .projected_shuffle, bits: bits, left: parent, right: right, condition: mapped, value: u64(i * input_count), height: height}
		// The outer projection builder appends/caches the final node and checks
		// depth again. Intermediate choices share the original guarded index.
		if i == factor - 1 { return node }
		if b.nodes.len >= max_memory_index_nodes || height > max_memory_index_depth - depth { return error('AIR memory index: interleave graph limit') }
		parent = b.nodes.len; b.nodes << node
	}
	return error('AIR memory index: interleave factor')
}
