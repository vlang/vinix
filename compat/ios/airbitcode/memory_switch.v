// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const max_memory_switch_cases = 64

// Operand/target ranges are checked by control preflight before this call.
fn (p IRTypedProgram) memory_switch_profile(op IRTypedInstruction, pools IRConstantPools, scope int, budget int) !int {
	if op.opcode != 0 || op.indices_count != 0 || op.operands_count < 1 || op.operands_count > max_memory_switch_cases + 1 || op.targets_count != op.operands_count { return error('AIR memory execution: switch shape/case limit') }
	bits := p.integer_bits(op.source_type)!
	if p.operands[op.operands_start].type_index != op.source_type { return error('AIR memory execution: switch condition type') }
	cases := op.operands_count - 1; work := cases * (cases + 1) / 2
	if work > budget { return error('AIR memory execution: switch validation work limit') }
	mut values := [64]u64{}
	for i in 0 .. cases {
		operand := p.operands[op.operands_start + 1 + i]
		if operand.type_index != op.source_type { return error('AIR memory execution: switch case type') }
		value := pools.lookup(scope, operand.number)!
		if value.kind != .constant || value.type_index != op.source_type { return error('AIR memory execution: literal switch case required') }
		c := pools.constants[value.constant_index]
		if c.type_index != op.source_type || c.bits != bits || c.splat || c.kind !in [.zero, .integer]! || (c.kind == .integer && (c.words_count != 1 || c.words_start < 0 || c.words_start >= pools.words.len)) { return error('AIR memory execution: defined scalar switch case required') }
		values[i] = pools.scalar_bits(value.constant_index)! & constant_mask(bits)
		for j in 0 .. i { if values[j] == values[i] { return error('AIR memory execution: duplicate switch case') } }
	}
	return work
}
