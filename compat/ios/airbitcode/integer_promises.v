// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// ICMP's serialized SameSign bit is valid only for scalar integer operands.
// Pointer comparisons keep their precomputed, flag-free memory profile.
fn (p IRTypedProgram) integer_compare_flag_mask(op IRTypedInstruction) u64 {
	if op.opcode < 32 || op.opcode > 41 || op.operands_count != 2 || op.operands_start < 0 || op.operands_start >= p.operands.len { return 0 }
	typ := p.operands[op.operands_start].type_index
	return if typ >= 0 && typ < p.types.len && p.types[typ].kind == .integer_t { u64(1) } else { u64(0) }
}
fn integer_compare_flags(op u32, flags u64, bits u32, a IntegerValue, b IntegerValue) !IntegerValue {
	if flags & ~u64(1) != 0 { return error('AIR integer: unsupported comparison flags') }
	result := integer_compare(op, bits, a, b)!
	if flags != 0 && !result.poison && (a.value ^ b.value) & (u64(1) << (bits - 1)) != 0 { return IntegerValue{poison: true} }
	return result
}
