// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (p IRTypedProgram) scalar_pair_frozen_constant(pools IRConstantPools, scope int, operand IRTypedOperand) !IntegerValue {
	p.scalar_overflow_element(operand.type_index)!
	value := pools.lookup(scope, operand.number)!
	if value.kind == .constant && value.type_index == operand.type_index {
		c := pools.constants[value.constant_index]
		if c.kind == .undef && c.type_index == operand.type_index && !c.splat { return IntegerValue{aggregate: true} }
	}
	return scalar_pair_freeze_value(p.scalar_pair_constant(pools, scope, operand)!)!
}

fn (p IRTypedProgram) scalar_pair_freeze(op IRTypedInstruction, base_id u32, pools IRConstantPools, scope int) ! {
	p.scalar_overflow_element(op.result_type)!
	if op.opcode != 0 || op.operands_count != 1 || op.targets_count != 0 || op.indices_count != 0 { return error('AIR pair: freeze shape') }
	operand := p.operands[op.operands_start]
	if operand.type_index != op.result_type { return error('AIR pair: freeze type mismatch') }
	if operand.number < base_id { p.scalar_pair_frozen_constant(pools, scope, operand)! }
}

fn scalar_pair_freeze_value(pair IntegerValue) !IntegerValue {
	if !pair.aggregate { return error('AIR pair: freeze aggregate required') }
	// Zero is a fixed choice for each poison field; defined neighbors survive.
	return IntegerValue{aggregate: true, value: if pair.poison { u64(0) } else { pair.value }, overflow: !pair.flag_poison && pair.overflow}
}

fn (m &IntegerMachine) read_pair_frozen(operand_index int) !IntegerValue {
	operand := m.p.operands[operand_index]
	if operand.number < m.bodies.scopes[m.scope].base_id { return m.p.scalar_pair_frozen_constant(m.pools, m.scope, operand)! }
	return scalar_pair_freeze_value(m.read_overflow(operand_index)!)!
}
