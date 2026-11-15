// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Flags are call-local: sharing a declaration never makes an SSA flag valid.
fn (p IRTypedProgram) vector_integer_abs_flag(ir IRModule, pools IRConstantPools, scope int, op IRTypedInstruction) !u64 {
	signature := ir.types[op.call_signature]
	flag := p.operands[op.operands_start + 2]
	if flag.type_index != ir.references[signature.refs_start + 2] || p.integer_bits(flag.type_index)! != 1 { return error('AIR vector intrinsic: abs i1 flag required') }
	value := pools.lookup(scope, flag.number)!
	if value.kind != .constant { return error('AIR vector intrinsic: constant abs flag required') }
	constant := pools.constants[value.constant_index]
	if constant.type_index != flag.type_index || constant.splat || constant.kind !in [.zero, .integer]! { return error('AIR vector intrinsic: invalid abs flag') }
	bits := pools.scalar_bits(value.constant_index)!
	if bits > 1 { return error('AIR vector intrinsic: abs flag outside i1') }
	return bits
}

fn (p IRTypedProgram) vector_integer_abs_profile(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies,
	scope int, index int, op IRTypedInstruction, count int, bits u32, remaining int) !int {
	work := p.vector_integer_unary_profile(ir, stream, pools, bodies, scope, index, op, count, bits, remaining)!
	p.vector_integer_abs_flag(ir, pools, scope, op)!
	return work
}

fn integer_abs_vector(source ScalarVectorValue, bits u32, count int, minimum_poison u64) !ScalarVectorValue {
	if minimum_poison > 1 { return error('AIR vector intrinsic: abs flag outside i1') }
	vector_float_intrinsic_key(.iabs, count, bits)!
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		if source.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector intrinsic: undef source lane') }
		a := source.lanes[lane]
		if a.aggregate || a.vector { return error('AIR vector intrinsic: scalar lanes required') }
		result.lanes[lane] = if a.poison { IntegerValue{poison: true} } else { scalar_integer_abs_value(bits, a.value, minimum_poison)! }
	}
	return result
}
