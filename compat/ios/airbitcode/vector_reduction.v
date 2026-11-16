// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const vector_reduction_cache_base = 25280

enum IntegerVectorReduction { sum product bit_and bit_or bit_xor smin smax umin umax }

fn vector_reduction_name(name string) !(IntegerVectorReduction, int, u32) {
	prefixes := ['llvm.vector.reduce.add.v', 'llvm.vector.reduce.mul.v', 'llvm.vector.reduce.and.v', 'llvm.vector.reduce.or.v', 'llvm.vector.reduce.xor.v', 'llvm.vector.reduce.smin.v', 'llvm.vector.reduce.smax.v', 'llvm.vector.reduce.umin.v', 'llvm.vector.reduce.umax.v']!
	for i, prefix in prefixes {
		if name.starts_with(prefix) { count, bits := vector_integer_overload(name, prefix.len)!; return unsafe { IntegerVectorReduction(i) }, count, bits }
	}
	return error('AIR vector reduction: integer reduction name required')
}
fn vector_reduction_key(id IntegerVectorReduction, count int, bits u32) !int {
	if int(id) < 0 || int(id) > 8 || count < 1 || count > 16 || bits < 1 || bits > 64 { return error('AIR vector reduction: cache shape') }
	return vector_reduction_cache_base + int(id) * 1024 + int(bits - 1) * 16 + count - 1
}
fn vector_reduction_call(ir IRModule, op IRTypedInstruction) bool {
	return op.callee_function >= 0 && op.callee_function < ir.functions.len && ir.functions[op.callee_function].name.starts_with('llvm.vector.reduce.')
}

// Reductions produce scalar SSA values and consume source plus one result lane
// of work, without allocating a vector construction slot.
fn (p IRTypedProgram) vector_reduction_profile(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, remaining int) !(int, int, u64) {
	if op.callee_function < 0 || op.callee_function >= ir.functions.len { return error('AIR vector reduction: callee index') }
	id, count, bits := vector_reduction_name(ir.functions[op.callee_function].name)!
	work, attributes := p.vector_reduction_shape(ir, stream, pools, bodies, scope, index, op, count, bits, false, false, remaining)!
	return work, vector_reduction_key(id, count, bits)!, attributes
}
fn (p IRTypedProgram) vector_reduction_shape(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, count int, bits u32, floating bool, seeded bool, remaining int) !(int, u64) {
	arity := if seeded { 3 } else { 2 }
	if op.flags != 32768 || op.opcode != 0 || op.is_volatile || op.calling_convention != 0 || op.fast_math_flags != 0 || op.attribute_set != 0 || op.targets_count != 0 || op.indices_count != 0 || op.callee_function < 0 || op.callee_function >= ir.functions.len || op.operands_start < 0 || op.operands_start > p.operands.len || op.operands_count != arity || op.operands_count > p.operands.len - op.operands_start { return error('AIR vector reduction: ordinary unflagged direct call required') }
	f := ir.functions[op.callee_function]
	if !f.declaration || f.calling_convention != 0 || f.linkage != 0 || f.signature != op.call_signature || f.signature < 0 || f.signature >= ir.types.len || f.record < 0 || f.record >= stream.records.len { return error('AIR vector reduction: declaration signature/header') }
	callee := p.operands[op.operands_start]
	if callee.number >= u32(pools.declarations.len) || pools.declarations[int(callee.number)] != f.record || callee.type_index < 0 || callee.type_index >= p.types.len || p.types[callee.type_index].kind != .pointer_t || p.types[callee.type_index].address_space != 0 { return error('AIR vector reduction: direct declaration identity') }
	signature := ir.types[f.signature]
	if signature.kind != .function_t || signature.vararg || signature.refs_count != arity || signature.refs_start < 0 || signature.refs_start > ir.references.len || signature.refs_count > ir.references.len - signature.refs_start || ir.references[signature.refs_start] != op.result_type { return error('AIR vector reduction: signature/arity') }
	source := p.operands[op.operands_start + arity - 1]
	if seeded && (p.operands[op.operands_start + 1].type_index != op.result_type || ir.references[signature.refs_start + 1] != op.result_type) { return error('AIR vector reduction: seed type identity') }
	if source.type_index != ir.references[signature.refs_start + arity - 1] || p.execution_bits(op.result_type, floating)! != bits { return error('AIR vector reduction: signature types') }
	element, source_bits, source_count := p.scalar_vector_type(source.type_index, floating, 16)!
	if element != op.result_type || (floating && p.types[element].kind !in [.half_t, .float_t]!) || (!floating && p.types[element].kind != .integer_t) || source_bits != bits || source_count != count { return error('AIR vector reduction: name/type mismatch') }
	work := arity - 1 + p.vector_source_profile(stream, pools, bodies, scope, index, source, floating, remaining - arity + 1)!
	raw := stream.records[f.record]
	if raw.code != 8 || raw.values_count < 10 { return error('AIR vector reduction: declaration record') }
	return work, ir_values(stream, raw)[6]
}
fn reduced_integer_vector(id IntegerVectorReduction, source ScalarVectorValue, bits u32, count int) !IntegerValue {
	vector_reduction_key(id, count, bits)!
	mut result := IntegerValue{}
	for lane in 0 .. count {
		if source.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector reduction: undef source lane') }
		a := source.lanes[lane]
		if a.aggregate || a.vector { return error('AIR vector reduction: scalar lanes required') }
		if lane == 0 { result = IntegerValue{value: a.value & constant_mask(bits), poison: a.poison}; continue }
		if result.poison || a.poison { result = IntegerValue{poison: true}; continue }
		result = match id {
			.sum { integer_binary(0, bits, result, a)! }
			.product { integer_binary(2, bits, result, a)! }
			.bit_and { integer_binary(10, bits, result, a)! }
			.bit_or { integer_binary(11, bits, result, a)! }
			.bit_xor { integer_binary(12, bits, result, a)! }
			else {
				operation := match id { .smin { ScalarIntrinsic.smin } .smax { ScalarIntrinsic.smax } .umin { ScalarIntrinsic.umin } else { ScalarIntrinsic.umax } }
				IntegerValue{value: scalar_intrinsic_value(operation, bits, result.value, a.value)!}
			}
		}
	}
	return result
}
fn (m &IntegerMachine) reduction_value(ir IRModule, stream Stream, op IRTypedInstruction) !IntegerValue {
	if number_vector_reduction_call(ir, op) {
		id, count, bits := number_vector_reduction_name(ir.functions[op.callee_function].name)!
		return reduced_floating_vector(id, m.read_vector(stream, m.p.operands[op.operands_start + 1])!, bits, count)!
	}
	if sequential_vector_reduction_call(ir, op) {
		id, count, bits := sequential_vector_reduction_name(ir.functions[op.callee_function].name)!
		seed := m.read(op.operands_start + 1)!
		return reduced_sequential_vector(id, seed, m.read_vector(stream, m.p.operands[op.operands_start + 2])!, bits, count)!
	}
	if floating_vector_reduction_call(ir, op) {
		id, count, bits := floating_vector_reduction_name(ir.functions[op.callee_function].name)!
		return reduced_floating_vector(id, m.read_vector(stream, m.p.operands[op.operands_start + 1])!, bits, count)!
	}
	id, count, bits := vector_reduction_name(ir.functions[op.callee_function].name)!
	source := m.read_vector(stream, m.p.operands[op.operands_start + 1])!
	return reduced_integer_vector(id, source, bits, count)!
}
