// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_vector_select_arm_states_poison_conditions_and_snapshots() {
	mut checks := 0
	for count in 1 .. 17 { for states in 0 .. 16 {
		mut left := ScalarVectorValue{}; mut right := ScalarVectorValue{}
		for lane in 0 .. count { for side in 0 .. 2 {
			state := if side == 0 { states / 4 } else { states % 4 }
			value := IntegerValue{value: u64(lane + 1 + side * 16) * u64(0x9e3779b97f4a7c15), poison: state == 1 || (state == 3 && lane % 4 == 1)}
			undef := state == 2 || (state == 3 && lane % 4 == 2)
			if side == 0 { left.lanes[lane] = value; if undef { left.undef |= u16(1) << u32(lane) } } else { right.lanes[lane] = value; if undef { right.undef |= u16(1) << u32(lane) } }
		} }
		old_left := left; old_right := right
		for raw in [u64(0), 1, 2, 3, ~u64(0), u64(1) << 63]! { for poison in [false, true]! {
			result := selected_vector(left, right, IntegerValue{value: raw, poison: poison}, count)!
			assert left == old_left && right == old_right
			for lane in 0 .. count {
				if poison { assert result.lanes[lane].poison && result.undef == 0 } else { expected := if raw & 1 != 0 { left } else { right }; assert result.lanes[lane] == expected.lanes[lane] && result.undef == expected.undef }; checks++
			}
			// Updates and freezes of a result cannot mutate either original arm.
			inserted_vector(result, count, IntegerValue{}, IntegerValue{value: 31}, false)!
			frozen_vector(result, count)!
			assert left == old_left && right == old_right
		} }
	} }
	assert checks == 26112
	for count in [0, 17] { if _ := selected_vector(ScalarVectorValue{}, ScalarVectorValue{}, IntegerValue{}, count) { assert false, 'count guard' } }
	for condition in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { if _ := selected_vector(ScalarVectorValue{}, ScalarVectorValue{}, condition, 1) { assert false, 'condition guard' } }
	println('AIR-VECTOR-SELECT-STATES: ${checks} independent lane-state checks, all counts 1..16, both arms and condition bits, poison/undef/mixed arms, poison conditions, immutable snapshots and guards PASS')
}

fn test_vector_select_reads_only_the_chosen_arm() {
	p := IRTypedProgram{types: [IRType{kind: .integer_t, bits: 1}, IRType{kind: .integer_t, bits: 32}, IRType{kind: .vector_t, count: 2, refs_count: 1}], references: [1], operands: [IRTypedOperand{number: 5, type_index: 2}, IRTypedOperand{number: 6, type_index: 2}, IRTypedOperand{number: 7, type_index: 0}]}
	defer { p.free() }
	mut left := ScalarVectorValue{}; left.lanes[0] = IntegerValue{value: 0x7f800001}; left.lanes[1] = IntegerValue{poison: true}
	mut right := ScalarVectorValue{undef: 2}; right.lanes[0] = IntegerValue{value: 0x80000000}
	mut m := IntegerMachine{p: p, bodies: IRFunctionBodies{scopes: [IRBodyScope{base_id: 5}]}, values: [IntegerValue{vector: true, value: 0}, IntegerValue{vector: true, value: 1}, IntegerValue{value: 1}, IntegerValue{vector: true, value: 2}], known: [true, false, true, false], vectors: [left, right, ScalarVectorValue{}]}
	defer { unsafe { m.values.free(); m.known.free(); m.vectors.free(); m.bodies.scopes.free() } }
	inst := IRInstruction{has_result: true, next_value: 8}; op := IRTypedInstruction{result_type: 2, operands_count: 3}
	assert m.select_vector_value(Stream{}, inst, op)! == IntegerValue{vector: true, value: 2} && m.vectors[2] == left
	m.values[2] = IntegerValue{value: 0}; m.known[0] = false; m.known[1] = true
	m.select_vector_value(Stream{}, inst, op)!
	assert m.vectors[2] == right && m.vectors[0] == left && m.vectors[1] == right
	m.values[2] = IntegerValue{poison: true}; m.known[1] = false
	m.select_vector_value(Stream{}, inst, op)!
	assert m.vectors[2].lanes[0].poison && m.vectors[2].lanes[1].poison && m.vectors[2].undef == 0
	m.known[2] = false
	if _ := m.select_vector_value(Stream{}, inst, op) { assert false, 'condition availability guard' }
	println('AIR-VECTOR-SELECT-LAZY: unavailable unchosen arms, poison conditions read neither arm, source snapshots and condition availability PASS')
}
