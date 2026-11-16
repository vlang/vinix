// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_scalar_vector_bitcast_classification_and_split_profiles() {
	p := IRTypedProgram{
		types: [IRType{kind: .integer_t, bits: 32}, IRType{kind: .integer_t, bits: 8}, IRType{kind: .vector_t, count: 4, refs_count: 1}, IRType{kind: .float_t}, IRType{kind: .half_t}, IRType{kind: .vector_t, count: 2, refs_start: 1, refs_count: 1}, IRType{kind: .integer_t, bits: 128}, IRType{kind: .pointer_t}]
		references: [1, 4]
		operands: [IRTypedOperand{type_index: 0}, IRTypedOperand{type_index: 2}, IRTypedOperand{type_index: 3}, IRTypedOperand{type_index: 6}, IRTypedOperand{type_index: 7}]
	}
	for source in [0, 2] { for dest in [2, 5] {
		op := IRTypedInstruction{opcode: 11, operands_count: 1, operands_start: source, result_type: dest}
		assert p.scalar_vector_bitcast(op)
		assert p.scalar_vector_bitcast_profile(Stream{}, IRConstantPools{}, IRFunctionBodies{}, 0, 0, op, true, 16)! == if dest == 2 { 5 } else { 3 }
		if source == 0 && dest == 2 { assert p.scalar_vector_bitcast_profile(Stream{}, IRConstantPools{}, IRFunctionBodies{}, 0, 0, op, false, 5)! == 5 }
		else { if _ := p.scalar_vector_bitcast_profile(Stream{}, IRConstantPools{}, IRFunctionBodies{}, 0, 0, op, false, 16) { assert false } }
		if _ := p.scalar_vector_bitcast_profile(Stream{}, IRConstantPools{}, IRFunctionBodies{}, 0, 0, op, true, if dest == 2 { 4 } else { 2 }) { assert false }
		for changed in [IRTypedInstruction{...op, flags: 1}, IRTypedInstruction{...op, opcode: 1}, IRTypedInstruction{...op, indices_count: 1}, IRTypedInstruction{...op, targets_count: 1}, IRTypedInstruction{...op, operands_count: 2}] {
			if _ := p.scalar_vector_bitcast_profile(Stream{}, IRConstantPools{}, IRFunctionBodies{}, 0, 0, changed, true, 16) { assert false }
		}
	} }
	for op in [IRTypedInstruction{opcode: 11, operands_count: 1, operands_start: -1, result_type: 2}, IRTypedInstruction{opcode: 11, operands_count: 1, operands_start: 10, result_type: 2}, IRTypedInstruction{opcode: 11, operands_count: 1, result_type: -1}, IRTypedInstruction{opcode: 11, operands_count: 1, result_type: 0}, IRTypedInstruction{opcode: 11, operands_count: 1, operands_start: 1, result_type: 2}] { assert !p.scalar_vector_bitcast(op) }
	for source in [3, 4] { op := IRTypedInstruction{opcode: 11, operands_count: 1, operands_start: source, result_type: 2}; if _ := p.scalar_vector_bitcast_profile(Stream{}, IRConstantPools{}, IRFunctionBodies{}, 0, 0, op, true, 16) { assert false } }
	println('AIR-SCALAR-VECTOR-BITCAST-PROFILE: shape classification, integer/mixed scalar splits, exact work and metadata/width/type guards PASS')
}

fn test_scalar_vector_bitcast_packed_values_and_states() {
	mut values := 0; mut states := 0
	for bits in u32(1) .. 65 { for count in 1 .. 17 {
		if bits * u32(count) > 64 { continue }
		total := bits * u32(count)
		for sample in 0 .. 8 {
			word := [u64(0), 1, ~u64(0), u64(1) << (total - 1), 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15, 0x7f8000017c018000, 0x0123456789abcdef]![sample]
			mut source := ScalarVectorValue{}; source.lanes[0] = IntegerValue{value: word}
			split := reshaped_bitcast_vector(source, total, 1, bits, count)!
			for lane in 0 .. count {
				mut expected := u64(0)
				for bit in u32(0) .. bits { expected |= ((word >> (u32(lane) * bits + bit)) & 1) << bit }
				assert split.lanes[lane] == IntegerValue{value: expected}; values++
			}
			packed := reshaped_bitcast_vector(split, bits, count, total, 1)!
			assert packed.lanes[0] == IntegerValue{value: word & constant_mask(total)}; values++
		}
		for target in 0 .. count {
			mut source := ScalarVectorValue{}; source.lanes[target] = IntegerValue{poison: true}
			packed := reshaped_bitcast_vector(source, bits, count, total, 1)!
			assert packed.lanes[0].poison
			spread := reshaped_bitcast_vector(packed, total, 1, bits, count)!
			for lane in 0 .. count { assert spread.lanes[lane].poison; states++ }
			source.undef = u16(1) << u32(target)
			if _ := reshaped_bitcast_vector(source, bits, count, total, 1) { assert false }; states++
		}
	} }
	println('AIR-SCALAR-VECTOR-BITCAST-VALUES: ${values} independent packed/split values and round trips; ${states} poison spreading/undef states across every supported integer shape PASS')
}
