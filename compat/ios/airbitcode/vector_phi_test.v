// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_vector_phi_parallel_snapshots_and_storage() {
	mut checks := 0
	for bits in u32(1) .. 65 { for count in 1 .. 17 { for state in 0 .. 4 {
		p := IRTypedProgram{types: [IRType{kind: .integer_t, bits: bits}, IRType{kind: .vector_t, count: u32(count), refs_count: 1}], references: [0], operands: [IRTypedOperand{number: 5, type_index: 1}, IRTypedOperand{number: 6, type_index: 1}, IRTypedOperand{number: 7, type_index: 1}]}
		mut initial := [3]ScalarVectorValue{}
		for side in 0 .. 3 { for lane in 0 .. count {
			initial[side].lanes[lane] = IntegerValue{value: u64(lane + side * 17) & constant_mask(bits), poison: state == 1 || (state == 3 && lane % 4 == 1)}
			if state == 2 || (state == 3 && lane % 4 == 2) { initial[side].undef |= u16(1) << u32(lane) }
		} }
		mut m := IntegerMachine{p: p, bodies: IRFunctionBodies{scopes: [IRBodyScope{base_id: 5}]}, values: [IntegerValue{vector: true, value: 0}, IntegerValue{vector: true, value: 1}, IntegerValue{vector: true, value: 2}], known: [true, true, true], vectors: [initial[0], initial[1], initial[2]]}
		mut snapshots := []ScalarVectorValue{len: 3}
		for visit in 1 .. 8 {
			mut pending := [3]IntegerValue{}
			for side in 0 .. 3 { pending[side] = m.read_phi(Stream{}, (side + 1) % 3, mut snapshots, side)! }
			for side in 0 .. 3 { m.put_phi(IRInstruction{next_value: u32(5 + side)}, pending[side], snapshots)! }
			for side in 0 .. 3 {
				expected := initial[(side + visit) % 3]
				assert m.values[side] == IntegerValue{vector: true, value: u64(side)} && m.known[side]
				assert m.vectors[side].undef == expected.undef
				for lane in 0 .. count { assert m.vectors[side].lanes[lane] == expected.lanes[lane]; checks++ }
			}
		}
		if _ := m.read_phi(Stream{}, 0, mut snapshots, 3) { assert false }
		if _ := m.put_phi(IRInstruction{next_value: 5}, IntegerValue{vector: true, value: 3}, snapshots) { assert false }
		m.known[0] = false
		if _ := m.read_phi(Stream{}, 0, mut snapshots, 0) { assert false }
		p.free(); unsafe { m.bodies.scopes.free(); m.values.free(); m.known.free(); m.vectors.free(); snapshots.free() }
	} } }
	assert checks == 731136
	println('AIR-VECTOR-PHI-SNAPSHOTS: ${checks} independent lane/state checks, i1..i64 and counts 1..16, seven three-way rotations, poison/undef preservation, stable owned slots and snapshot/availability guards PASS')
}
