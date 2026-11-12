// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_pair_insert_repair_independence_and_overwrite_identities() {
	mut count := 0
	for bits in u32(1) .. 65 { for raw in [u64(0), 1, 2, 3, u64(1) << (bits - 1), ~u64(0), u64(0xaaaaaaaaaaaaaaaa), 0x5555555555555555]! {
		for state in 0 .. 4 {
			base := IntegerValue{value: raw & constant_mask(bits), overflow: raw & 1 != 0, poison: state & 1 != 0, flag_poison: state & 2 != 0, aggregate: true}
			data := IntegerValue{value: raw, poison: base.poison}; flag := IntegerValue{value: u64(base.overflow), poison: base.flag_poison}
			// Reinsert both original fields in either order: every tag must survive.
			x := scalar_pair_insert_value(scalar_pair_insert_value(base, data, 0, bits)!, flag, 1, bits)!
			y := scalar_pair_insert_value(scalar_pair_insert_value(base, flag, 1, bits)!, data, 0, bits)!
			assert x == base && y == base
			// Poisoning then restoring one field cannot affect its neighbor.
			for field in u32(0) .. 2 {
				poisoned := scalar_pair_insert_value(base, IntegerValue{poison: true}, field, bits)!
				restored := scalar_pair_insert_value(poisoned, if field == 0 { data } else { flag }, field, bits)!
				assert restored == base && poisoned.aggregate
				if field == 0 { assert poisoned.poison && poisoned.flag_poison == base.flag_poison && poisoned.overflow == base.overflow }
				else { assert poisoned.flag_poison && poisoned.poison == base.poison && poisoned.value == base.value }
			}
			// Replacing both fields repairs even an entirely poisoned pair.
			fixed := scalar_pair_insert_value(scalar_pair_insert_value(base, IntegerValue{value: raw}, 0, bits)!, IntegerValue{value: raw}, 1, bits)!
			assert fixed.aggregate && !fixed.poison && !fixed.flag_poison && fixed.value == raw & constant_mask(bits) && fixed.overflow == (raw & 1 != 0)
			count++
		}
	} }
	assert count == 2048 && sizeof(IntegerValue) == 16
	for bits in [u32(0), 65]! { if _ := scalar_pair_insert_value(IntegerValue{aggregate: true}, IntegerValue{}, 0, bits) { assert false, 'insert width' } }
	if _ := scalar_pair_insert_value(IntegerValue{}, IntegerValue{}, 0, 32) { assert false, 'scalar base' }
	if _ := scalar_pair_insert_value(IntegerValue{aggregate: true}, IntegerValue{aggregate: true}, 0, 32) { assert false, 'aggregate replacement' }
	if _ := scalar_pair_insert_value(IntegerValue{aggregate: true}, IntegerValue{}, 2, 32) { assert false, 'field outside pair' }
	println('AIR-PAIR-INSERT-VALUES: 2048 width/pattern/poison states, both overwrite orders, field independence, repair, masking, 16-byte slots and operation guards PASS')
}

fn test_pair_insert_profile_shape_origin_and_field_types() {
	mut p := IRTypedProgram{types: [IRType{kind: .integer_t, bits: 32}, IRType{kind: .integer_t, bits: 1}, IRType{kind: .struct_t, refs_count: 2}], references: [0, 1], operands: [IRTypedOperand{number: 5, type_index: 2}, IRTypedOperand{number: 0, type_index: 0}], indices: [u32(0)]}
	defer { p.free() }
	op := IRTypedInstruction{result_type: 2, source_type: 2, operands_count: 2, indices_count: 1}
	p.scalar_pair_insert(op, 5, IRConstantPools{}, 0)!
	for changed in [IRTypedInstruction{...op, result_type: 0}, IRTypedInstruction{...op, source_type: -1}, IRTypedInstruction{...op, opcode: 1}, IRTypedInstruction{...op, operands_count: 1}, IRTypedInstruction{...op, targets_count: 1}, IRTypedInstruction{...op, indices_count: 0}, IRTypedInstruction{...op, indices_start: -1}] {
		if _ := p.scalar_pair_insert(changed, 5, IRConstantPools{}, 0) { assert false, 'insert profile shape' }
	}
	p.indices[0] = 1
	if _ := p.scalar_pair_insert(op, 5, IRConstantPools{}, 0) { assert false, 'i32 replacement in i1 field' }
	p.operands[1] = IRTypedOperand{number: 0, type_index: 1}; p.scalar_pair_insert(op, 5, IRConstantPools{}, 0)!
	p.indices[0] = 2
	if _ := p.scalar_pair_insert(op, 5, IRConstantPools{}, 0) { assert false, 'out-of-range insert' }
	p.indices[0] = 1; p.operands[0] = IRTypedOperand{number: 4, type_index: 2}
	if _ := p.scalar_pair_insert(op, 5, IRConstantPools{}, 0) { assert false, 'unavailable pair constant' }
	println('AIR-PAIR-INSERT-PROFILE: both scalar field types, literal index, source/result identity, shape and source scope guards PASS')
}
