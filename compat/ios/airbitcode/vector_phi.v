// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (p IRTypedProgram) vector_phi_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, op IRTypedInstruction, mixed bool, remaining int) !int {
	if op.flags != 0 || op.opcode != 0 || op.fast_math_flags != 0 || op.is_volatile || op.indices_count != 0 || op.operands_count < 1 || op.targets_count != op.operands_count || op.operands_start < 0 || op.operands_start > p.operands.len || op.operands_count > p.operands.len - op.operands_start || op.targets_start < 0 || op.targets_start > p.targets.len || op.targets_count > p.targets.len - op.targets_start { return error('AIR vector: PHI shape/flags') }
	_, _, count := p.scalar_vector_type(op.result_type, mixed, remaining)!
	s := bodies.scopes[scope]
	mut work := count
	for i in 0 .. op.operands_count {
		source := p.operands[op.operands_start + i]
		if source.type_index != op.result_type { return error('AIR vector: PHI type identity') }
		target := p.targets[op.targets_start + i]
		if target < s.blocks_start || target >= s.blocks_start + s.blocks_count || target >= bodies.blocks.len { return error('AIR vector: PHI predecessor range') }
		pred := bodies.blocks[target]
		if pred.scope != scope || pred.first < s.instructions_start || pred.count < 1 || pred.first > s.instructions_start + s.instructions_count || pred.count > s.instructions_start + s.instructions_count - pred.first { return error('AIR vector: PHI predecessor block') }
		// Incoming uses occur on predecessor edges, so a loop's producer may
		// follow this PHI in the instruction stream, but must precede its branch.
		work += p.vector_source_profile(stream, pools, bodies, scope, pred.first + pred.count - 1, source, mixed, remaining - work)!
	}
	return work
}

// Snapshot every selected vector before any PHI result slot is overwritten.
// Pending scalar tags refer only to this call's separate snapshot buffer.
fn (m &IntegerMachine) read_phi(stream Stream, incoming int, mut snapshots []ScalarVectorValue, used int) !IntegerValue {
	if m.p.types[m.p.operands[incoming].type_index].kind != .vector_t { return m.read_flow(incoming)! }
	if used < 0 || used >= snapshots.len { return error('AIR vector: PHI snapshot limit') }
	snapshots[used] = m.read_vector(stream, m.p.operands[incoming])!
	value := IntegerValue{vector: true, value: u64(used)}
	return value
}
fn (mut m IntegerMachine) put_phi(inst IRInstruction, value IntegerValue, snapshots []ScalarVectorValue) ! {
	if !value.vector { m.put(inst, value); return }
	if value.value >= u64(snapshots.len) { return error('AIR vector: PHI snapshot slot') }
	result := m.store_vector_value(inst, snapshots[int(value.value)])!
	m.put(inst, result)
}
