// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (p IRTypedProgram) memory_literal(pools IRConstantPools, scope int, operand int) !u64 {
	o := p.operands[operand]
	value := pools.lookup(scope, o.number)!
	if value.kind != .constant { return error('AIR memory intrinsic: literal required') }
	c := pools.constants[value.constant_index]
	if c.type_index != o.type_index || c.splat || c.kind !in [.zero, .integer]! { return error('AIR memory intrinsic: defined scalar literal required') }
	return pools.scalar_bits(value.constant_index)!
}

// A void direct memset, exact overloaded name/signature and literal length.
// The destination is resolved separately through the usual virtual pointers.
fn (p IRTypedProgram) memory_memset_call(ir IRModule, stream Stream, pools IRConstantPools, op IRTypedInstruction, scope int) !(u64, u64, int) {
	if op.flags != 32768 || op.calling_convention != 0 || op.fast_math_flags != 0 || op.attribute_set != 0 || op.opcode != 0 || op.indices_count != 0 || op.result_type != -1 || op.operands_count != 5 || op.callee_function < 0 || op.callee_function >= ir.functions.len { return error('AIR memory intrinsic: ordinary void direct call required') }
	f := ir.functions[op.callee_function]
	if !f.declaration || f.calling_convention != 0 || f.linkage != 0 || f.signature != op.call_signature || f.signature < 0 || f.signature >= ir.types.len || f.record < 0 || f.record >= stream.records.len { return error('AIR memory intrinsic: declaration signature/header') }
	callee := p.operands[op.operands_start]
	if callee.number >= u32(pools.declarations.len) || pools.declarations[int(callee.number)] != f.record { return error('AIR memory intrinsic: direct declaration identity') }
	pointer := p.gep_type(callee.type_index)!
	if pointer.kind != .pointer_t || pointer.address_space != 0 { return error('AIR memory intrinsic: default callee pointer required') }
	sig := ir.types[f.signature]
	if sig.kind != .function_t || sig.vararg || sig.refs_count != 5 || sig.refs_start < 0 || sig.refs_start > ir.references.len || sig.refs_count > ir.references.len - sig.refs_start || p.gep_type(ir.references[sig.refs_start])!.kind != .void_t { return error('AIR memory intrinsic: fixed void signature required') }
	for i in 0 .. 4 {
		if p.operands[op.operands_start + i + 1].type_index != ir.references[sig.refs_start + i + 1] { return error('AIR memory intrinsic: argument type identity') }
	}
	dest := p.gep_type(p.operands[op.operands_start + 1].type_index)!
	if dest.kind != .pointer_t || dest.address_space > 2 || p.integer_bits(p.operands[op.operands_start + 2].type_index)! != 8 || p.integer_bits(p.operands[op.operands_start + 4].type_index)! != 1 { return error('AIR memory intrinsic: memset argument types') }
	bits := p.integer_bits(p.operands[op.operands_start + 3].type_index)!
	if bits !in [u32(32), 64]! { return error('AIR memory intrinsic: memset length type') }
	key := int(dest.address_space) * 2 + int(bits == 64)
	if f.name != ['llvm.memset.p0.i32', 'llvm.memset.p0.i64', 'llvm.memset.p1.i32', 'llvm.memset.p1.i64', 'llvm.memset.p2.i32', 'llvm.memset.p2.i64']![key] { return error('AIR memory intrinsic: memset name/type') }
	if p.memory_literal(pools, scope, op.operands_start + 4)! != 0 { return error('AIR memory intrinsic: nonvolatile memset required') }
	length := p.memory_literal(pools, scope, op.operands_start + 3)!
	if length > u64(max_integer_execution_steps) { return error('AIR memory intrinsic: memset byte budget') }
	raw := stream.records[f.record]
	if raw.code != 8 || raw.values_count < 10 { return error('AIR memory intrinsic: function declaration record') }
	return length, ir_values(stream, raw)[6], key
}
