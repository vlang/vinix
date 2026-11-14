// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_memory_switch_case_limits_literals_duplicates_and_work() {
	mut constants := []IRConstant{len: 64}; mut words := []u64{len: 64}
	mut p := IRTypedProgram{types: [IRType{kind: .integer_t, bits: 8}, IRType{kind: .float_t}, IRType{kind: .integer_t, bits: 128}], operands: []IRTypedOperand{len: 66}, targets: []int{len: 66}}
	defer { p.free() }
	for i in 0 .. 64 { words[i] = u64(i); constants[i] = IRConstant{kind: .integer, type_index: 0, bits: 8, words_start: i, words_count: 1}; p.operands[i + 1] = IRTypedOperand{number: u32(i), type_index: 0} }
	p.operands[0] = IRTypedOperand{number: 100, type_index: 0}
	pools := IRConstantPools{module_values: 64, scopes: [IRConstantScope{active: true, count: 64}], constants: constants, words: words}
	defer { pools.free() }
	op := IRTypedInstruction{status: .decoded, source_type: 0, operands_count: 65, targets_count: 65}
	assert p.memory_switch_profile(op, pools, 0, 2080)! == 2080
	assert p.memory_switch_profile(IRTypedInstruction{...op, operands_count: 1, targets_count: 1}, pools, 0, 0)! == 0
	if _ := p.memory_switch_profile(op, pools, 0, 2079) { assert false, 'validation budget' }
	for changed in [IRTypedInstruction{...op, opcode: 1}, IRTypedInstruction{...op, indices_count: 1}, IRTypedInstruction{...op, operands_count: 0}, IRTypedInstruction{...op, operands_count: 66, targets_count: 66}, IRTypedInstruction{...op, targets_count: 64}, IRTypedInstruction{...op, source_type: -1}, IRTypedInstruction{...op, source_type: 1}, IRTypedInstruction{...op, source_type: 2}] {
		if _ := p.memory_switch_profile(changed, pools, 0, 2080) { assert false, 'switch profile shape/type' }
	}
	for slot in [0, 1] { saved := p.operands[slot]; p.operands[slot] = IRTypedOperand{...saved, type_index: 1}; if _ := p.memory_switch_profile(op, pools, 0, 2080) { assert false, 'operand type' }; p.operands[slot] = saved }
	saved := p.operands[1]; p.operands[1] = IRTypedOperand{...saved, number: 100}; if _ := p.memory_switch_profile(op, pools, 0, 2080) { assert false, 'nonconstant case' }; p.operands[1] = saved
	c := constants[0]
	for changed in [IRConstant{...c, kind: .poison}, IRConstant{...c, kind: .undef}, IRConstant{...c, kind: .floating}, IRConstant{...c, kind: .aggregate}, IRConstant{...c, type_index: 1}, IRConstant{...c, splat: true}, IRConstant{...c, bits: 7}, IRConstant{...c, words_count: 0}, IRConstant{...c, words_start: -1}, IRConstant{...c, words_start: 64}] {
		constants[0] = changed; if _ := p.memory_switch_profile(op, pools, 0, 2080) { assert false, 'case constant metadata' }
	}; constants[0] = c
	words[1] = 0; if _ := p.memory_switch_profile(op, pools, 0, 2080) { assert false, 'duplicate case' }
	words[1] = 256; if _ := p.memory_switch_profile(op, pools, 0, 2080) { assert false, 'masked duplicate case' }; words[1] = 1
	constants[0] = IRConstant{...c, kind: .zero, words_count: 0}; assert p.memory_switch_profile(op, pools, 0, 2080)! == 2080
	println('AIR-MEMORY-SWITCH-PROFILE: empty/64-case edges, 65-case rejection, exact work budget, scalar types, literal kinds/widths/word bounds, zero and masked duplicate cases PASS')
}
