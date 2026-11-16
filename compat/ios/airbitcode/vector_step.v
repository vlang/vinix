// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const vector_step_cache_base = vector_interleave_cache_base + 1716

fn vector_step_name(name string) !(int, u32) {
	if !name.starts_with('llvm.stepvector.v') { return error('AIR stepvector: canonical name required') }
	count, bits := vector_integer_overload(name, 17)!
	if bits < 8 { return error('AIR stepvector: elements must be at least i8') }
	return count, bits
}
fn vector_step_key(count int, bits u32) !int {
	if count < 1 || count > 16 || bits < 8 || bits > 64 { return error('AIR stepvector: cache shape') }
	return vector_step_cache_base + (int(bits) - 8) * 16 + count - 1
}
// Common validation checks exact direct identity, signature and call metadata,
// including the callee-only operand list of this zero-argument intrinsic.
fn (p IRTypedProgram) vector_step_profile(ir IRModule, op IRTypedInstruction, remaining int) !(int, int) {
	count, bits := vector_step_name(ir.functions[op.callee_function].name)!
	_, actual_bits, actual := p.scalar_vector_type(op.result_type, false, remaining)!
	if actual != count || actual_bits != bits { return error('AIR stepvector: name/type identity') }
	return count, vector_step_key(count, bits)!
}
fn step_vector(count int, bits u32) !ScalarVectorValue {
	vector_step_key(count, bits)!
	mut result := ScalarVectorValue{}
	for lane in 0 .. count { result.lanes[lane] = IntegerValue{value: u64(lane)} }
	return result
}
fn (mut b MemoryIndexBuilder) project_vector_step(source IRTypedOperand, selector int, producer int) !MemoryIndexNode {
	op := b.p.instructions[producer]
	b.p.vector_float_intrinsic_profile(b.ir, b.stream, b.pools, b.bodies, b.scope, producer, op, false, 16)!
	_, bits, count := b.p.scalar_vector_type(source.type_index, false, 16)!
	mut first := u64(0); mut second := u64(0)
	for lane in 0 .. count {
		if lane < 8 { first |= u64(lane) << u32(lane * 8) } else { second |= u64(lane) << u32((lane - 8) * 8) }
	}
	// The existing selector evaluator poisons invalid indices before returning
	// the packed lane value. The outer builder checks height, capacity and cache.
	return MemoryIndexNode{kind: .shuffle_selector, bits: bits, left: selector, source_bits: u32(count), value: first, flags: second, height: b.nodes[selector].height + 1}
}
