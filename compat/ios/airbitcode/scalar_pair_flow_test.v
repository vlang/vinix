// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_scalar_pair_flow_profile_shapes_and_types() {
	mut p := IRTypedProgram{types: [IRType{kind: .integer_t, bits: 32}, IRType{kind: .integer_t, bits: 1}, IRType{kind: .struct_t, refs_count: 2}], references: [0, 1], operands: [IRTypedOperand{number: 5, type_index: 2}, IRTypedOperand{number: 6, type_index: 2}, IRTypedOperand{number: 0, type_index: 1}]}
	defer { p.free() }
	op := IRTypedInstruction{result_type: 2, operands_count: 3}
	p.scalar_pair_flow(op, 5, true)!
	p.scalar_pair_flow(IRTypedInstruction{...op, operands_count: 2}, 5, false)!
	for changed in [IRTypedInstruction{...op, operands_count: 2}, IRTypedInstruction{...op, operands_count: 0}, IRTypedInstruction{...op, opcode: 1}, IRTypedInstruction{...op, targets_count: 1}, IRTypedInstruction{...op, result_type: 0}] {
		if _ := p.scalar_pair_flow(changed, 5, true) { assert false, 'pair select shape' }
	}
	for slot in 0 .. 2 {
		saved := p.operands[slot]
		for changed in [IRTypedOperand{...saved, number: 4}, IRTypedOperand{...saved, type_index: 0}] {
			p.operands[slot] = changed
			if _ := p.scalar_pair_flow(op, 5, true) { assert false, 'select pair operand' }
			if _ := p.scalar_pair_flow(IRTypedInstruction{...op, operands_count: 2}, 5, false) { assert false, 'PHI pair operand' }
		}; p.operands[slot] = saved
	}
	saved := p.operands[2]; p.operands[2] = IRTypedOperand{...saved, type_index: 0}
	if _ := p.scalar_pair_flow(op, 5, true) { assert false, 'pair select condition not i1' }
	println('AIR-PAIR-FLOW-PROFILE: matching literal pairs, select/PHI arities, opcode, targets, scalar condition and instruction-result guards PASS')
}

fn test_scalar_pair_flow_runtime_tags_and_availability() {
	mut p := IRTypedProgram{types: [IRType{kind: .integer_t, bits: 32}, IRType{kind: .integer_t, bits: 1}, IRType{kind: .struct_t, refs_count: 2}], references: [0, 1], operands: [IRTypedOperand{number: 5, type_index: 2}, IRTypedOperand{number: 6, type_index: 2}, IRTypedOperand{number: 7, type_index: 0}, IRTypedOperand{number: 5, type_index: 0}]}
	defer { p.free() }
	mut m := IntegerMachine{p: p, binary32: true, bodies: IRFunctionBodies{scopes: [IRBodyScope{base_id: 5}]}, values: [IntegerValue{value: 0xffffffff, overflow: true, aggregate: true}, IntegerValue{poison: true, aggregate: true, flag_poison: true}, IntegerValue{value: 99}], known: [true, true, true]}
	defer { unsafe { m.values.free(); m.known.free(); m.bodies.scopes.free() } }
	pair := m.read_flow(0)!; poisoned := m.read_flow(1)!; scalar := m.read_flow(2)!
	assert sizeof(IntegerValue) == 16 && pair.aggregate && pair.value == 0xffffffff && pair.overflow && !pair.poison
	assert poisoned.aggregate && poisoned.poison && poisoned.flag_poison && !scalar.aggregate && scalar.value == 99 && !scalar.poison
	if _ := m.read(3) { assert false, 'pair slot used as scalar' }
	if _ := m.read_overflow(2) { assert false, 'scalar slot used as pair' }
	m.known[0] = false
	if _ := m.read_flow(0) { assert false, 'unknown pair slot' }
	println('AIR-PAIR-FLOW-VALUES: complete value/overflow/poison/tag copies, unchanged 16-byte slots, scalar separation and availability guards PASS')
}
