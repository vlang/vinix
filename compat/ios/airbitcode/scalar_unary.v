// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (p IRTypedProgram) scalar_unary_profile(op IRTypedInstruction, freeze bool, mixed bool) ! {
	if op.flags != 0 || op.opcode != 0 || op.operands_count != 1 || op.operands_start < 0 || op.operands_start >= p.operands.len || p.operands[op.operands_start].type_index != op.result_type { return error('AIR scalar: unary result/arity/type/flags') }
	p.execution_bits(op.result_type, mixed)!
	if !freeze && (!mixed || p.types[op.result_type].kind !in [.half_t, .float_t]!) { return error('AIR scalar: floating fneg required') }
}
fn (m &IntegerMachine) fneg_value(op IRTypedInstruction) !IntegerValue {
	input := m.read(op.operands_start)!
	bits := m.p.execution_bits(op.result_type, m.binary32)!
	return IntegerValue{value: input.value ^ (u64(1) << (bits - 1)), poison: input.poison}
}
