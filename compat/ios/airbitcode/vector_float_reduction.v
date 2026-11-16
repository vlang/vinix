// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const floating_vector_reduction_cache_base = vector_reduction_cache_base + 9216

fn floating_vector_reduction_name(name string) !(ScalarIntrinsic, int, u32) {
	if !name.starts_with('llvm.vector.reduce.fminimum.v') && !name.starts_with('llvm.vector.reduce.fmaximum.v') { return error('AIR vector reduction: floating min/max name required') }
	count, bits := vector_float_overload(name, 29)!
	return if name[21] == `i` { ScalarIntrinsic.minimum } else { ScalarIntrinsic.maximum }, count, bits
}
fn floating_vector_reduction_call(ir IRModule, op IRTypedInstruction) bool {
	if op.callee_function < 0 || op.callee_function >= ir.functions.len { return false }
	name := ir.functions[op.callee_function].name
	return name.starts_with('llvm.vector.reduce.fminimum.') || name.starts_with('llvm.vector.reduce.fmaximum.')
}
fn floating_vector_reduction_key(id ScalarIntrinsic, count int, bits u32) !int {
	if id !in [.minimum, .maximum]! || count < 1 || count > 16 || bits !in [u32(16), 32]! { return error('AIR vector reduction: floating cache shape') }
	return floating_vector_reduction_cache_base + int(id == .maximum) * 32 + int(bits == 16) * 16 + count - 1
}
fn (p IRTypedProgram) scalar_vector_reduction_profile(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !(int, int, u64) {
	if number_vector_reduction_call(ir, op) {
		if !mixed { return error('AIR vector reduction: mixed floating execution required') }
		id, count, bits := number_vector_reduction_name(ir.functions[op.callee_function].name)!
		work, attributes := p.vector_reduction_shape(ir, stream, pools, bodies, scope, index, op, count, bits, true, false, remaining)!
		return work, number_vector_reduction_key(id, count, bits)!, attributes
	}
	if sequential_vector_reduction_call(ir, op) {
		if !mixed { return error('AIR vector reduction: mixed floating execution required') }
		id, count, bits := sequential_vector_reduction_name(ir.functions[op.callee_function].name)!
		work, attributes := p.vector_reduction_shape(ir, stream, pools, bodies, scope, index, op, count, bits, true, true, remaining)!
		return work, sequential_vector_reduction_key(id, count, bits)!, attributes
	}
	if !floating_vector_reduction_call(ir, op) { return p.vector_reduction_profile(ir, stream, pools, bodies, scope, index, op, remaining)! }
	if !mixed { return error('AIR vector reduction: mixed floating execution required') }
	id, count, bits := floating_vector_reduction_name(ir.functions[op.callee_function].name)!
	work, attributes := p.vector_reduction_shape(ir, stream, pools, bodies, scope, index, op, count, bits, true, false, remaining)!
	return work, floating_vector_reduction_key(id, count, bits)!, attributes
}
fn reduced_floating_vector(id ScalarIntrinsic, source ScalarVectorValue, bits u32, count int) !IntegerValue {
	if id in [.minnum, .maxnum, .minimumnum, .maximumnum]! { number_vector_reduction_key(id, count, bits)! } else { floating_vector_reduction_key(id, count, bits)! }
	// fmin/fmax choose the existing scalar minnum/maxnum refinement: treat
	// signaling NaNs as quiet and prefer a number. This fixed left fold is a
	// permitted reduction order; poison and undef still observe every lane.
	// fminimumnum/fmaximumnum require this numeric NaN preference directly.
	mut result := IntegerValue{}
	for lane in 0 .. count {
		if source.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector reduction: undef floating source lane') }
		a := source.lanes[lane]
		if a.aggregate || a.vector { return error('AIR vector reduction: scalar floating lanes required') }
		// A single lane is an identity, including its NaN payload/signaling bit.
		if lane == 0 { result = IntegerValue{value: a.value & constant_mask(bits), poison: a.poison}; continue }
		result = if result.poison || a.poison { IntegerValue{poison: true} } else { IntegerValue{value: scalar_intrinsic_value(id, bits, result.value, a.value & constant_mask(bits))!} }
	}
	return result
}
