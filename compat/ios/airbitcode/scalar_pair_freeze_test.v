// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_pair_freeze_field_independence_and_idempotence() {
	mut count := 0
	for bits in u32(1) .. 65 { for raw in [u64(0), 1, 2, 3, u64(1) << (bits - 1), ~u64(0), u64(0xaaaaaaaaaaaaaaaa), 0x5555555555555555]! { for state in 0 .. 4 {
		pair := IntegerValue{aggregate: true, value: raw & constant_mask(bits), overflow: raw & 1 != 0, poison: state & 1 != 0, flag_poison: state & 2 != 0}
		frozen := scalar_pair_freeze_value(pair)!
		assert frozen.aggregate && !frozen.poison && !frozen.flag_poison
		assert frozen.value == if pair.poison { u64(0) } else { pair.value }
		assert frozen.overflow == (!pair.flag_poison && pair.overflow)
		assert scalar_pair_freeze_value(frozen)! == frozen
		count++
	} } }
	assert count == 2048 && sizeof(IntegerValue) == 16
	if _ := scalar_pair_freeze_value(IntegerValue{}) { assert false, 'scalar frozen as pair' }
	println('AIR-PAIR-FREEZE-VALUES: 2048 width/pattern/poison states, defined neighbors, independent zero choices, idempotence and 16-byte values PASS')
}

fn test_pair_freeze_profile_constant_scope_and_runtime_guards() {
	mut p := IRTypedProgram{types: [IRType{kind: .integer_t, bits: 32}, IRType{kind: .integer_t, bits: 1}, IRType{kind: .struct_t, refs_count: 2}], references: [0, 1], operands: [IRTypedOperand{number: 5, type_index: 2}, IRTypedOperand{number: 0, type_index: 2}, IRTypedOperand{number: 2, type_index: 2}]}
	defer { p.free() }
	mut constants := [IRConstant{kind: .zero, type_index: 2}, IRConstant{kind: .undef, type_index: 2, scope: 1, number: 2}]
	pools := IRConstantPools{module_values: 1, scopes: [IRConstantScope{active: true, count: 1}, IRConstantScope{active: true, arguments_count: 1, base_id: 2, first: 1, count: 1}], arguments: [0], constants: constants}
	defer { pools.free() }
	op := IRTypedInstruction{result_type: 2, operands_count: 1}
	p.scalar_pair_freeze(op, 3, pools, 1)!
	for changed in [IRTypedInstruction{...op, opcode: 1}, IRTypedInstruction{...op, operands_count: 0}, IRTypedInstruction{...op, operands_count: 2}, IRTypedInstruction{...op, targets_count: 1}, IRTypedInstruction{...op, indices_count: 1}, IRTypedInstruction{...op, result_type: 0}] {
		if _ := p.scalar_pair_freeze(changed, 3, pools, 1) { assert false, 'pair freeze shape' }
	}
	mut m := IntegerMachine{p: p, pools: pools, scope: 1, binary32: true, bodies: IRFunctionBodies{scopes: [IRBodyScope{}, IRBodyScope{base_id: 3}]}, values: [IntegerValue{}, IntegerValue{}, IntegerValue{aggregate: true, value: 19, overflow: true, flag_poison: true}], known: [false, false, true]}
	defer { unsafe { m.values.free(); m.known.free(); m.bodies.scopes.free() } }
	assert m.read_pair_frozen(0)! == IntegerValue{aggregate: true, value: 19}
	assert m.read_pair_frozen(1)! == IntegerValue{aggregate: true}
	assert m.read_pair_frozen(2)! == IntegerValue{aggregate: true}
	p.scalar_pair_freeze(IRTypedInstruction{...op, operands_start: 1}, 3, pools, 1)!
	p.scalar_pair_freeze(IRTypedInstruction{...op, operands_start: 2}, 3, pools, 1)!
	if _ := m.read_overflow(2) { assert false, 'ordinary read accepted undef' }
	for kind in [IRConstantKind.zero, .poison, .undef]! {
		constants[1] = IRConstant{kind: kind, type_index: 2, scope: 1, number: 2}
		assert m.read_pair_frozen(2)! == IntegerValue{aggregate: true}
	}
	for c in [IRConstant{kind: .undef, type_index: 0}, IRConstant{kind: .undef, type_index: 2, splat: true}, IRConstant{kind: .aggregate, type_index: 2}, IRConstant{kind: .opaque, type_index: 2}] {
		constants[1] = c
		if _ := m.read_pair_frozen(2) { assert false, 'pair freeze constant metadata' }
	}
	constants[1] = IRConstant{kind: .undef, type_index: 2, scope: 1, number: 2}
	if _ := p.scalar_pair_frozen_constant(pools, 0, p.operands[2]) { assert false, 'local undef visible in module' }
	for operand in [IRTypedOperand{number: 1, type_index: 2}, IRTypedOperand{number: 99, type_index: 2}, IRTypedOperand{number: 2, type_index: 0}] {
		if _ := p.scalar_pair_frozen_constant(pools, 1, operand) { assert false, 'pair freeze argument/range/type' }
	}
	saved := p.operands[0]; p.operands[0] = IRTypedOperand{...saved, type_index: 0}
	if _ := p.scalar_pair_freeze(op, 3, pools, 1) { assert false, 'pair freeze source type' }; p.operands[0] = saved
	m.known[2] = false; if _ := m.read_pair_frozen(0) { assert false, 'unavailable freeze input' }
	m.known[2] = true; m.values[2] = IntegerValue{value: 19}; if _ := m.read_pair_frozen(0) { assert false, 'scalar freeze input' }
	original := p.types[2]
	for changed in [IRType{...original, packed: true}, IRType{...original, name: 'named'}, IRType{...original, refs_count: 1}] {
		p.types[2] = changed; if _ := p.scalar_pair_freeze(op, 3, pools, 1) { assert false, 'pair freeze layout' }
	}
	println('AIR-PAIR-FREEZE-GUARDS: shape/type/layout, scoped zero/poison/undef, freeze-only undef, constant metadata, availability and scalar separation PASS')
}
