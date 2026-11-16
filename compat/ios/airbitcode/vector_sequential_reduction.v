// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const sequential_vector_reduction_cache_base = floating_vector_reduction_cache_base + 64

enum FloatingSequentialReduction { sum product }

fn sequential_vector_reduction_name(name string) !(FloatingSequentialReduction, int, u32) {
	if !name.starts_with('llvm.vector.reduce.fadd.v') && !name.starts_with('llvm.vector.reduce.fmul.v') { return error('AIR vector reduction: sequential floating name required') }
	count, bits := vector_float_overload(name, 'llvm.vector.reduce.fadd.v'.len)!
	return if name[20] == `a` { FloatingSequentialReduction.sum } else { FloatingSequentialReduction.product }, count, bits
}
fn sequential_vector_reduction_call(ir IRModule, op IRTypedInstruction) bool {
	if op.callee_function < 0 || op.callee_function >= ir.functions.len { return false }
	name := ir.functions[op.callee_function].name
	return name.starts_with('llvm.vector.reduce.fadd.') || name.starts_with('llvm.vector.reduce.fmul.')
}
fn sequential_vector_reduction_key(id FloatingSequentialReduction, count int, bits u32) !int {
	if int(id) < 0 || int(id) > 1 || count < 1 || count > 16 || bits !in [u32(16), 32]! { return error('AIR vector reduction: sequential cache shape') }
	return sequential_vector_reduction_cache_base + int(id) * 32 + int(bits == 16) * 16 + count - 1
}
fn reduced_sequential_vector(id FloatingSequentialReduction, seed IntegerValue, source ScalarVectorValue, bits u32, count int) !IntegerValue {
	sequential_vector_reduction_key(id, count, bits)!
	if seed.aggregate || seed.vector { return error('AIR vector reduction: scalar floating seed required') }
	mut result := IntegerValue{value: seed.value & constant_mask(bits), poison: seed.poison}
	for lane in 0 .. count {
		// Observe every lane even after poison or a NaN accumulator. A later
		// result freeze cannot suppress this instruction's earlier undef error.
		if source.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector reduction: undef sequential source lane') }
		a := source.lanes[lane]
		if a.aggregate || a.vector { return error('AIR vector reduction: scalar floating lanes required') }
		opcode := if id == .sum { u32(0) } else { u32(2) }
		result = if result.poison || a.poison { IntegerValue{poison: true} } else if bits == 16 { IntegerValue{value: binary16_binary(opcode, u16(result.value), u16(a.value))!} } else { IntegerValue{value: binary32_binary(opcode, u32(result.value), u32(a.value))!} }
	}
	return result
}
