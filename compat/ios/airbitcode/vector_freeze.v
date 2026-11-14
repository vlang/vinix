// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (p IRTypedProgram) vector_construction(code u64, op IRTypedInstruction) bool {
	return code in [u64(7), 8]! || (code in [u64(5), 29, 58]! && op.result_type >= 0 && op.result_type < p.types.len && p.types[op.result_type].kind == .vector_t)
}
fn (p IRTypedProgram) vector_freeze_profile(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !int {
	vector_operation_shape(p, op, 1)!
	source := p.operands[op.operands_start]
	if source.type_index != op.result_type { return error('AIR vector: freeze type identity') }
	return p.vector_source_profile(stream, pools, bodies, scope, index, source, mixed, remaining)!
}
fn frozen_vector(source ScalarVectorValue, count int) !ScalarVectorValue {
	if count < 1 || count > 16 { return error('AIR vector: freeze count') }
	mut result := source
	result.undef = 0
	for lane in 0 .. count {
		if source.lanes[lane].aggregate || source.lanes[lane].vector { return error('AIR vector: scalar freeze lane required') }
		// Zero is a permitted fixed choice for each indeterminate lane.
		if source.lanes[lane].poison || source.undef & (u16(1) << u32(lane)) != 0 { result.lanes[lane] = IntegerValue{} }
	}
	return result
}
fn (mut m IntegerMachine) freeze_vector_value(stream Stream, inst IRInstruction, op IRTypedInstruction) !IntegerValue {
	source := m.read_vector(stream, m.p.operands[op.operands_start])!
	return m.store_vector_value(inst, frozen_vector(source, int(m.p.types[op.result_type].count))!)!
}
