// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_pair_constants_scopes_tags_and_all_consumers() {
	mut p := IRTypedProgram{types: [IRType{kind: .integer_t, bits: 32}, IRType{kind: .integer_t, bits: 1}, IRType{kind: .struct_t, refs_count: 2}], references: [0, 1], operands: [IRTypedOperand{number: 0, type_index: 2}, IRTypedOperand{number: 2, type_index: 2}, IRTypedOperand{number: 1, type_index: 1}], indices: [u32(1)]}
	defer { p.free() }
	pools := IRConstantPools{module_values: 1, scopes: [IRConstantScope{active: true, count: 1}, IRConstantScope{active: true, arguments_count: 1, base_id: 2, first: 1, count: 1}], arguments: [1], constants: [IRConstant{kind: .zero, type_index: 2}, IRConstant{kind: .poison, type_index: 2, scope: 1, number: 2}]}
	defer { pools.free() }
	zero := p.scalar_pair_constant(pools, 1, p.operands[0])!; poison := p.scalar_pair_constant(pools, 1, p.operands[1])!
	assert zero.aggregate && zero.value == 0 && !zero.overflow && !zero.poison && !zero.flag_poison
	assert poison.aggregate && poison.poison && poison.flag_poison
	p.scalar_pair_source(pools, 1, 3, p.operands[0], 2)!
	p.scalar_pair_source(pools, 1, 3, p.operands[1], 2)!
	p.scalar_pair_flow(IRTypedInstruction{result_type: 2, operands_count: 3}, 3, true, pools, 1)!
	p.scalar_pair_flow(IRTypedInstruction{result_type: 2, operands_count: 2}, 3, false, pools, 1)!
	p.operands[1] = IRTypedOperand{number: 1, type_index: 1}
	p.scalar_pair_insert(IRTypedInstruction{result_type: 2, source_type: 2, operands_count: 2, indices_count: 1}, 3, pools, 1)!
	p.operands << IRTypedOperand{number: 2, type_index: 2}
	m := IntegerMachine{p: p, pools: pools, scope: 1, binary32: true, bodies: IRFunctionBodies{scopes: [IRBodyScope{}, IRBodyScope{base_id: 3}]}}
	defer { unsafe { m.bodies.scopes.free() } }
	assert m.read_overflow(0)! == zero && m.read_flow(0)! == zero && m.read_overflow(3)! == poison && m.read_flow(3)! == poison
	for operand in [IRTypedOperand{number: 1, type_index: 2}, IRTypedOperand{number: 99, type_index: 2}, IRTypedOperand{number: 0, type_index: 0}] {
		if _ := p.scalar_pair_constant(pools, 1, operand) { assert false, 'argument/missing/scalar constant accepted as pair' }
	}
	if _ := p.scalar_pair_source(pools, 1, 3, p.operands[0], 0) { assert false, 'pair source type mismatch' }
	if _ := p.scalar_pair_constant(pools, 0, IRTypedOperand{number: 2, type_index: 2}) { assert false, 'local constant visible in module scope' }
	assert sizeof(IntegerValue) == 16
	println('AIR-PAIR-CONSTANT-SCOPES: module zero/local poison, both tags, select/PHI/insert/read dispatch, type/argument/scope/range guards and 16-byte values PASS')
}

fn test_pair_constant_kinds_layouts_and_metadata_fail_closed() {
	mut p := IRTypedProgram{types: [IRType{kind: .integer_t, bits: 32}, IRType{kind: .integer_t, bits: 1}, IRType{kind: .struct_t, refs_count: 2}], references: [0, 1]}
	defer { p.free() }
	mut constants := [IRConstant{kind: .zero, type_index: 2}]
	pools := IRConstantPools{scopes: [IRConstantScope{active: true, count: 1}], constants: constants, module_values: 1}; defer { pools.free() }
	operand := IRTypedOperand{number: 0, type_index: 2}
	for kind in [IRConstantKind.undef, .integer, .floating, .aggregate, .opaque, .data]! {
		constants[0] = IRConstant{kind: kind, type_index: 2}
		if _ := p.scalar_pair_constant(pools, 0, operand) { assert false, 'unsupported pair constant kind' }
	}
	for c in [IRConstant{kind: .zero, type_index: 0}, IRConstant{kind: .poison, type_index: 2, splat: true}]! {
		constants[0] = c
		if _ := p.scalar_pair_constant(pools, 0, operand) { assert false, 'constant metadata mismatch' }
	}
	constants[0] = IRConstant{kind: .zero, type_index: 2}; original := p.types[2]
	for changed in [IRType{...original, packed: true}, IRType{...original, name: 'named'}, IRType{...original, refs_count: 1}] {
		p.types[2] = changed
		if _ := p.scalar_pair_constant(pools, 0, operand) { assert false, 'unsupported pair layout' }
	}
	println('AIR-PAIR-CONSTANT-GUARDS: six unsupported kinds, type/splat and packed/named/field-count guards PASS')
}
