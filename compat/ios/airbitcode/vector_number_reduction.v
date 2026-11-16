// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const number_vector_reduction_cache_base = sequential_vector_reduction_cache_base + 64

fn number_vector_reduction_name(name string) !(ScalarIntrinsic, int, u32) {
	if name.starts_with('llvm.vector.reduce.fminimumnum.v') || name.starts_with('llvm.vector.reduce.fmaximumnum.v') {
		count, bits := vector_float_overload(name, 'llvm.vector.reduce.fminimumnum.v'.len)!
		return if name[21] == `i` { ScalarIntrinsic.minimumnum } else { ScalarIntrinsic.maximumnum }, count, bits
	}
	if !name.starts_with('llvm.vector.reduce.fmin.v') && !name.starts_with('llvm.vector.reduce.fmax.v') { return error('AIR vector reduction: number min/max name required') }
	count, bits := vector_float_overload(name, 'llvm.vector.reduce.fmin.v'.len)!
	return if name[21] == `i` { ScalarIntrinsic.minnum } else { ScalarIntrinsic.maxnum }, count, bits
}
fn number_vector_reduction_call(ir IRModule, op IRTypedInstruction) bool {
	if op.callee_function < 0 || op.callee_function >= ir.functions.len { return false }
	name := ir.functions[op.callee_function].name
	return name.starts_with('llvm.vector.reduce.fmin.') || name.starts_with('llvm.vector.reduce.fmax.') || name.starts_with('llvm.vector.reduce.fminimumnum.') || name.starts_with('llvm.vector.reduce.fmaximumnum.')
}
fn number_vector_reduction_key(id ScalarIntrinsic, count int, bits u32) !int {
	if id !in [.minnum, .maxnum, .minimumnum, .maximumnum]! || count < 1 || count > 16 || bits !in [u32(16), 32]! { return error('AIR vector reduction: number cache shape') }
	// Keep declaration identities distinct even when the chosen legacy
	// refinement has the same value semantics as the modern operation.
	return number_vector_reduction_cache_base + int(id in [.minimumnum, .maximumnum]!) * 64 + int(id in [.maxnum, .maximumnum]!) * 32 + int(bits == 16) * 16 + count - 1
}
