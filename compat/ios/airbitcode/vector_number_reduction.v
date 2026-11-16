// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const number_vector_reduction_cache_base = sequential_vector_reduction_cache_base + 64

fn number_vector_reduction_name(name string) !(ScalarIntrinsic, int, u32) {
	if !name.starts_with('llvm.vector.reduce.fmin.v') && !name.starts_with('llvm.vector.reduce.fmax.v') { return error('AIR vector reduction: number min/max name required') }
	count, bits := vector_float_overload(name, 'llvm.vector.reduce.fmin.v'.len)!
	return if name[21] == `i` { ScalarIntrinsic.minnum } else { ScalarIntrinsic.maxnum }, count, bits
}
fn number_vector_reduction_call(ir IRModule, op IRTypedInstruction) bool {
	if op.callee_function < 0 || op.callee_function >= ir.functions.len { return false }
	name := ir.functions[op.callee_function].name
	return name.starts_with('llvm.vector.reduce.fmin.') || name.starts_with('llvm.vector.reduce.fmax.')
}
fn number_vector_reduction_key(id ScalarIntrinsic, count int, bits u32) !int {
	if id !in [.minnum, .maxnum]! || count < 1 || count > 16 || bits !in [u32(16), 32]! { return error('AIR vector reduction: number cache shape') }
	return number_vector_reduction_cache_base + int(id == .maxnum) * 32 + int(bits == 16) * 16 + count - 1
}
