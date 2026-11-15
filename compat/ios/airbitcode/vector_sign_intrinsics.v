// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const vector_sign_intrinsic_slots = 64
const vector_float_intrinsic_slots = vector_sign_intrinsic_slots + 224 + 32 + 64

// Parse canonical overloads without allocating substrings or formatted names.
fn vector_sign_intrinsic_name(name string) !(ScalarIntrinsic, int, u32) {
	id := if name.starts_with('llvm.fabs.v') { ScalarIntrinsic.fabs } else if name.starts_with('llvm.copysign.v') { ScalarIntrinsic.copysign } else { return error('AIR vector intrinsic: unsupported name') }
	count, bits := vector_float_overload(name, if id == .fabs { 11 } else { 15 })!
	return id, count, bits
}
fn vector_float_overload(name string, start int) !(int, u32) {
	mut offset := start
	if offset < 0 || offset >= name.len || name[offset] == `0` { return error('AIR vector intrinsic: canonical lane count required') }
	mut count := 0
	for offset < name.len && name[offset] >= `0` && name[offset] <= `9` {
		count = count * 10 + int(name[offset] - `0`); offset++
		if count > 16 { return error('AIR vector intrinsic: lane count') }
	}
	if count < 1 || name.len - offset != 3 || name[offset] != `f` || !((name[offset + 1] == `1` && name[offset + 2] == `6`) || (name[offset + 1] == `3` && name[offset + 2] == `2`)) { return error('AIR vector intrinsic: half/float overload required') }
	return count, if name[offset + 1] == `1` { u32(16) } else { u32(32) }
}
fn vector_sign_intrinsic_key(id ScalarIntrinsic, count int, bits u32) !int {
	if id !in [.fabs, .copysign]! || count < 1 || count > 16 || bits !in [u32(16), 32]! { return error('AIR vector intrinsic: cache shape') }
	return int(id == .copysign) * 32 + int(bits == 16) * 16 + count - 1
}
// Validate direct identity, exact signature and every source before execution.
// Return lane work, cache key and declaration attributes for the bounded scanner.
fn (p IRTypedProgram) vector_float_intrinsic_profile(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !(int, int, u64) {
	if !mixed || op.flags != 32768 || op.opcode != 0 || op.calling_convention != 0 || op.fast_math_flags != 0 || op.attribute_set != 0 || op.targets_count != 0 || op.indices_count != 0 || op.callee_function < 0 || op.callee_function >= ir.functions.len || op.operands_start < 0 || op.operands_start > p.operands.len || op.operands_count < 2 || op.operands_count > p.operands.len - op.operands_start { return error('AIR vector intrinsic: ordinary unflagged direct call required') }
	f := ir.functions[op.callee_function]; id, count, bits := vector_float_intrinsic_name(f.name)!
	if !f.declaration || f.calling_convention != 0 || f.linkage != 0 || f.signature != op.call_signature || f.signature < 0 || f.signature >= ir.types.len || f.record < 0 || f.record >= stream.records.len { return error('AIR vector intrinsic: declaration signature/header') }
	callee := p.operands[op.operands_start]
	if callee.number >= u32(pools.declarations.len) || pools.declarations[int(callee.number)] != f.record || callee.type_index < 0 || callee.type_index >= p.types.len || p.types[callee.type_index].kind != .pointer_t || p.types[callee.type_index].address_space != 0 { return error('AIR vector intrinsic: direct declaration identity') }
	signature := ir.types[f.signature]; arity := scalar_intrinsic_arity(id)
	if signature.kind != .function_t || signature.vararg || signature.refs_count != arity + 1 || signature.refs_start < 0 || signature.refs_start > ir.references.len || signature.refs_count > ir.references.len - signature.refs_start || op.operands_count != arity + 1 || ir.references[signature.refs_start] != op.result_type { return error('AIR vector intrinsic: signature/arity') }
	element, actual_bits, actual_count := p.scalar_vector_type(op.result_type, mixed, remaining)!
	if count != actual_count || bits != actual_bits || p.types[element].kind !in [.half_t, .float_t]! { return error('AIR vector intrinsic: name/type mismatch') }
	mut work := count
	for i in 0 .. arity {
		source := p.operands[op.operands_start + i + 1]
		if ir.references[signature.refs_start + i + 1] != op.result_type || source.type_index != op.result_type { return error('AIR vector intrinsic: argument type identity') }
		work += p.vector_source_profile(stream, pools, bodies, scope, index, source, mixed, remaining - work)!
	}
	raw := stream.records[f.record]
	if raw.code != 8 || raw.values_count < 10 { return error('AIR vector intrinsic: declaration record') }
	return work, vector_float_intrinsic_key(id, count, bits)!, ir_values(stream, raw)[6]
}
fn sign_intrinsic_vector(id ScalarIntrinsic, left ScalarVectorValue, right ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
	vector_sign_intrinsic_key(id, count, bits)!
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		a := left.lanes[lane]; b := if id == .copysign { right.lanes[lane] } else { IntegerValue{} }
		if (left.undef | if id == .copysign { right.undef } else { u16(0) }) & (u16(1) << u32(lane)) != 0 { return error('AIR vector intrinsic: undef source lane') }
		if a.aggregate || a.vector || b.aggregate || b.vector { return error('AIR vector intrinsic: scalar lanes required') }
		result.lanes[lane] = if a.poison || b.poison { IntegerValue{poison: true} } else { IntegerValue{value: scalar_intrinsic_value(id, bits, a.value, b.value)!} }
	}
	return result
}
fn (mut m IntegerMachine) float_intrinsic_vector_value(ir IRModule, stream Stream, inst IRInstruction, op IRTypedInstruction) !IntegerValue {
	id, count, bits := vector_float_intrinsic_name(ir.functions[op.callee_function].name)!
	left := m.read_vector(stream, m.p.operands[op.operands_start + 1])!
	right := if scalar_intrinsic_arity(id) == 2 { m.read_vector(stream, m.p.operands[op.operands_start + 2])! } else { ScalarVectorValue{} }
	result := if id in [.fabs, .copysign]! { sign_intrinsic_vector(id, left, right, bits, count)! } else if id in [.minimum, .maximum]! { minmax_intrinsic_vector(id, left, right, bits, count)! } else if id == .sqrt { sqrt_intrinsic_vector(left, bits, count)! } else { rounding_intrinsic_vector(id, left, bits, count)! }
	return m.store_vector_value(inst, result)!
}
