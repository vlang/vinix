// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (p IRTypedProgram) scalar_pair_constant(pools IRConstantPools, scope int, operand IRTypedOperand) !IntegerValue {
	p.scalar_overflow_element(operand.type_index)!
	value := pools.lookup(scope, operand.number)!
	if value.kind != .constant || value.type_index != operand.type_index { return error('AIR pair: matching constant required') }
	c := pools.constants[value.constant_index]
	if c.type_index != operand.type_index || c.splat || c.kind !in [.zero, .poison]! { return error('AIR pair: only zero/poison constants supported') }
	return IntegerValue{aggregate: true, poison: c.kind == .poison, flag_poison: c.kind == .poison}
}

fn (p IRTypedProgram) scalar_pair_source(pools IRConstantPools, scope int, base_id u32, operand IRTypedOperand, expected int) ! {
	if operand.type_index != expected { return error('AIR pair: source type mismatch') }
	if operand.number < base_id { p.scalar_pair_constant(pools, scope, operand)! }
}
