// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_constant_vector_extract_data_widths_counts_and_masking() {
	mut p := IRTypedProgram{types: [IRType{kind: .integer_t, bits: 8}, IRType{kind: .integer_t, bits: 64}, IRType{kind: .vector_t, count: 4, refs_count: 1}], references: [0], operands: [IRTypedOperand{number: 0, type_index: 2}, IRTypedOperand{number: 1, type_index: 1}]}
	mut constants := [IRConstant{kind: .data, type_index: 2, bits: 8, words_count: 4}]; mut words := []u64{len: 16}
	pools := IRConstantPools{module_values: 1, scopes: [IRConstantScope{active: true}, IRConstantScope{active: true, base_id: 2, arguments_count: 1}], arguments: [1], constants: constants, words: words}
	bodies := IRFunctionBodies{scopes: [IRBodyScope{}, IRBodyScope{active: true, base_id: 2}]}; stream := Stream{}
	mut arguments := [u64(0)]
	defer { p.free(); pools.free(); bodies.free(); unsafe { arguments.free() } }
	op := IRTypedInstruction{result_type: 0, operands_count: 2}
	mut checks := 0
	for element in 0 .. 66 {
		bits := if element < 64 { u32(element + 1) } else if element == 64 { u32(16) } else { u32(32) }
		p.types[0] = if element < 64 { IRType{kind: .integer_t, bits: bits} } else if element == 64 { IRType{kind: .half_t} } else { IRType{kind: .float_t} }
		for lane in 0 .. 16 { words[lane] = (u64(lane + 1) * u64(0x9e3779b97f4a7c15)) & constant_mask(bits) }
		for count in 1 .. 17 {
			p.types[2] = IRType{kind: .vector_t, count: u64(count), refs_count: 1}; constants[0] = IRConstant{kind: .data, type_index: 2, bits: bits, words_count: count}
			for index_bits in u32(1) .. 65 {
				p.types[1] = IRType{kind: .integer_t, bits: index_bits}
				assert p.constant_extract_profile(stream, pools, bodies, 1, op, true, count)! == count
				if element < 64 { assert p.constant_extract_profile(stream, pools, bodies, 1, op, false, count)! == count } else { if _ := p.constant_extract_profile(stream, pools, bodies, 1, op, false, count) { assert false, 'integer API admitted FP lane' } }
				for index in u64(0) .. 20 {
					arguments[0] = index | ~constant_mask(index_bits)
					machine := IntegerMachine{p: p, pools: pools, bodies: bodies, scope: 1, arguments: arguments, binary32: true}
					result := machine.extract_constant_lane(stream, op)!
					expected := index & constant_mask(index_bits)
					assert result.poison == (expected >= u64(count)) && (result.poison || result.value == words[int(expected)]); checks++
				}
			}
		}
	}
	assert checks == 1351680
	println('AIR-CONSTANT-EXTRACT-DATA: ${checks} exact lane/index checks, all i1-i64/half/float lanes, counts 1..16, i1-i64 unsigned indices, masking, out-of-range poison and integer API isolation PASS')
}
fn test_constant_vector_extract_forms_and_guards() {
	mut p := IRTypedProgram{types: [IRType{kind: .integer_t, bits: 32}, IRType{kind: .integer_t, bits: 64}, IRType{kind: .vector_t, count: 4, refs_count: 1}], references: [0], operands: [IRTypedOperand{number: 0, type_index: 2}, IRTypedOperand{number: 5, type_index: 1}]}
	mut constants := [IRConstant{kind: .aggregate, type_index: 2, record: 0}, IRConstant{kind: .integer, type_index: 0, bits: 32, words_count: 1}, IRConstant{kind: .poison, type_index: 0, bits: 32}, IRConstant{kind: .undef, type_index: 0, bits: 32}, IRConstant{kind: .zero, type_index: 0, bits: 32}]
	words := [u64(17), 29, 31, 37]
	pools := IRConstantPools{module_values: 5, scopes: [IRConstantScope{active: true}, IRConstantScope{active: true, base_id: 6, arguments_count: 1}], arguments: [1], constants: constants, words: words}
	bodies := IRFunctionBodies{scopes: [IRBodyScope{}, IRBodyScope{active: true, base_id: 6}]}
	stream := Stream{records: [Record{code: 7, values_count: 4}], values: [u64(1), 2, 3, 4]}
	mut arguments := [u64(0)]; op := IRTypedInstruction{result_type: 0, operands_count: 2}
	defer { p.free(); pools.free(); bodies.free(); stream.free(); unsafe { arguments.free() } }
	assert p.constant_extract_profile(stream, pools, bodies, 1, op, true, 4)! == 4
	for index in u64(0) .. 5 {
		arguments[0] = index; machine := IntegerMachine{p: p, pools: pools, bodies: bodies, scope: 1, arguments: arguments, binary32: true}
		if index == 2 { if _ := machine.extract_constant_lane(stream, op) { assert false, 'selected undef' } } else { r := machine.extract_constant_lane(stream, op)!; assert r.poison == (index == 1 || index == 4) && (r.poison || r.value == if index == 0 { 17 } else { 0 }) }
	}
	for kind in [IRConstantKind.zero, .poison, .undef, .integer] {
		constants[0] = IRConstant{kind: kind, type_index: 2, bits: 32, words_count: if kind == .integer { 1 } else { 0 }, splat: kind == .integer}
		p.constant_extract_profile(stream, pools, bodies, 1, op, true, 4)!
		for index in [u64(0), 3, 4, ~u64(0)]! {
			arguments[0] = index; machine := IntegerMachine{p: p, pools: pools, bodies: bodies, scope: 1, arguments: arguments, binary32: true}
			if kind == .undef && index < 4 { if _ := machine.extract_constant_lane(stream, op) { assert false, 'whole undef' } } else { r := machine.extract_constant_lane(stream, op)!; assert r.poison == (kind == .poison || index >= 4) && (r.poison || r.value == if kind == .integer { 17 } else { 0 }) }
		}
	}
	constants[0] = IRConstant{kind: .aggregate, type_index: 2}
	for limit in [-1, 0, 3] { if _ := p.constant_extract_profile(stream, pools, bodies, 1, op, true, limit) { assert false, 'lane work bound' } }
	for changed in [IRTypedInstruction{...op, flags: 1}, IRTypedInstruction{...op, operands_count: 1}, IRTypedInstruction{...op, operands_start: -1}, IRTypedInstruction{...op, result_type: 1}, IRTypedInstruction{...op, indices_count: 1}, IRTypedInstruction{...op, targets_count: 1}] { if _ := p.constant_extract_profile(stream, pools, bodies, 1, changed, true, 100) { assert false, 'shape/type/flag guard' } }
	for changed in [IRType{kind: .array_t, count: 4, refs_count: 1}, IRType{kind: .vector_t, count: 4, refs_count: 1, scalable: true}, IRType{kind: .vector_t, count: 17, refs_count: 1}, IRType{kind: .vector_t, count: 0, refs_count: 1}, IRType{kind: .vector_t, count: 4, refs_count: 0}] { p.types[2] = changed; if _ := p.constant_extract_profile(stream, pools, bodies, 1, op, true, 100) { assert false, 'vector shape guard' } }
	p.types[2] = IRType{kind: .vector_t, count: 4, refs_count: 1}
	for source in [u32(5), 6]! { p.operands[0] = IRTypedOperand{number: source, type_index: 2}; if _ := p.constant_extract_profile(stream, pools, bodies, 1, op, true, 100) { assert false, 'nonliteral source' } }
	p.operands[0] = IRTypedOperand{number: 0, type_index: 2}
	saved := constants[2]; constants[2] = IRConstant{kind: .opaque, type_index: 0, bits: 32}
	if _ := p.constant_extract_profile(stream, pools, bodies, 1, op, true, 100) { assert false, 'unselected opaque lane admitted' }; constants[2] = saved
	for changed in [IRConstant{kind: .opaque, type_index: 2}, IRConstant{kind: .data, type_index: 2, bits: 32, words_count: 3}, IRConstant{kind: .data, type_index: 2, bits: 32, words_count: 4, words_start: 1}, IRConstant{kind: .integer, type_index: 2, bits: 32, words_count: 1}] { constants[0] = changed; if _ := p.constant_extract_profile(stream, pools, bodies, 1, op, true, 100) { assert false, 'constant encoding guard' } }
	println('AIR-CONSTANT-EXTRACT-GUARDS: aggregate/data/splat/zero/poison/undef, lazy lane selection, whole undef with out-of-range indices, work/shape/type/encoding guards and unselected opaque lanes PASS')
}
