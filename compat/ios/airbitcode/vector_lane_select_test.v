// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_vector_lane_select_states_and_snapshots() {
	mut checks := 0
	for count in 1 .. 17 { for pattern in 0 .. 81 {
		mut left := ScalarVectorValue{}; mut right := ScalarVectorValue{}; mut condition := ScalarVectorValue{}
		for lane in 0 .. count {
			state := (pattern / [1, 3, 9, 27]![lane % 4]) % 3
			condition.lanes[lane] = IntegerValue{value: u64(state) | (u64(lane) << 1), poison: state == 2}
			left.lanes[lane] = IntegerValue{value: u64(lane + 1) * u64(0x9e3779b97f4a7c15), poison: lane % 4 == 1}
			right.lanes[lane] = IntegerValue{value: ~left.lanes[lane].value, poison: lane % 4 == 2}
			if lane % 4 == 2 { left.undef |= u16(1) << u32(lane) }; if lane % 4 == 1 { right.undef |= u16(1) << u32(lane) }
		}
		old_left := left; old_right := right; old_condition := condition
		result := selected_vector_lanes(left, right, condition, count)!
		mut need_left := false; mut need_right := false
		for lane in 0 .. count {
			state := (pattern / [1, 3, 9, 27]![lane % 4]) % 3; bit := u16(1) << u32(lane)
			if state == 2 { assert result.lanes[lane].poison && result.undef & bit == 0 }
			else if state == 1 { assert result.lanes[lane] == left.lanes[lane] && result.undef & bit == left.undef & bit; need_left = true }
			else { assert result.lanes[lane] == right.lanes[lane] && result.undef & bit == right.undef & bit; need_right = true }; checks++
		}
		a, b := vector_select_arms(condition, count)!; assert a == need_left && b == need_right
		inserted_vector(result, count, IntegerValue{}, IntegerValue{value: 17}, false)!
		frozen_vector(result, count)!
		assert left == old_left && right == old_right && condition == old_condition
		for lane in 0 .. count {
			mut bad := condition; bad.undef |= u16(1) << u32(lane)
			if _ := selected_vector_lanes(left, right, bad, count) { assert false, 'undef condition lane admitted' }
		}
	} }
	assert checks == 11016
	for count in [0, 17] { if _, _ := vector_select_arms(ScalarVectorValue{}, count) { assert false, 'count guard' } }
	for lane in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] {
		mut bad := ScalarVectorValue{}; bad.lanes[0] = lane
		if _, _ := vector_select_arms(bad, 1) { assert false, 'condition lane guard' }
	}
	println('AIR-VECTOR-LANE-SELECT-STATES: ${checks} lane states, all counts 1..16, mixed conditions, localized poison, chosen undef, immutable snapshots, arm requirements and undef/count/tag guards PASS')
}

fn test_vector_lane_select_lazy_reader() {
	p := IRTypedProgram{types: [IRType{kind: .integer_t, bits: 1}, IRType{kind: .integer_t, bits: 32}, IRType{kind: .vector_t, count: 2, refs_count: 1}, IRType{kind: .vector_t, count: 2, refs_start: 1, refs_count: 1}], references: [1, 0], operands: [IRTypedOperand{number: 5, type_index: 2}, IRTypedOperand{number: 6, type_index: 2}, IRTypedOperand{number: 7, type_index: 3}]}
	defer { p.free() }
	mut left := ScalarVectorValue{}; left.lanes[0] = IntegerValue{value: 17}; left.lanes[1] = IntegerValue{poison: true}
	mut right := ScalarVectorValue{undef: 2}; right.lanes[0] = IntegerValue{value: 29}
	mut condition := ScalarVectorValue{}; condition.lanes[0] = IntegerValue{value: 1}; condition.lanes[1] = IntegerValue{poison: true}
	mut m := IntegerMachine{p: p, bodies: IRFunctionBodies{scopes: [IRBodyScope{base_id: 5}]}, values: [IntegerValue{vector: true, value: 0}, IntegerValue{vector: true, value: 1}, IntegerValue{vector: true, value: 2}, IntegerValue{vector: true, value: 3}], known: [true, false, true, false], vectors: [left, right, condition, ScalarVectorValue{}]}
	defer { unsafe { m.values.free(); m.known.free(); m.vectors.free(); m.bodies.scopes.free() } }
	inst := IRInstruction{has_result: true, next_value: 8}; op := IRTypedInstruction{result_type: 2, operands_count: 3}
	m.select_vector_value(Stream{}, inst, op)!
	assert m.vectors[3].lanes[0].value == 17 && m.vectors[3].lanes[1].poison
	m.vectors[2].lanes[0] = IntegerValue{}; m.known[0] = false; m.known[1] = true
	m.select_vector_value(Stream{}, inst, op)!
	assert m.vectors[3].lanes[0].value == 29 && m.vectors[3].lanes[1].poison
	m.vectors[2].lanes[0] = IntegerValue{poison: true}; m.known[1] = false
	m.select_vector_value(Stream{}, inst, op)!
	assert m.vectors[3].lanes[0].poison && m.vectors[3].lanes[1].poison && m.vectors[3].undef == 0
	m.vectors[2].undef = 2
	if _ := m.select_vector_value(Stream{}, inst, op) { assert false, 'undef condition lane' }
	assert m.vectors[0] == left && m.vectors[1] == right
	println('AIR-VECTOR-LANE-SELECT-LAZY: unneeded arms unavailable, all-poison conditions read neither, condition undef and source snapshots PASS')
}
