// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_vector_insert_lane_states_and_snapshots() {
	mut checks := 0
	for count in 1 .. 17 { for state in 0 .. 4 {
		mut source := ScalarVectorValue{}
		for lane in 0 .. count {
			source.lanes[lane] = IntegerValue{value: u64(lane + 1) * 17, poison: state == 1 || (state == 3 && lane % 4 == 1)}
			if state == 2 || (state == 3 && lane % 4 == 2) { source.undef |= u16(1) << u32(lane) }
		}
		original := source
		for index in u64(0) .. 20 { for replacement in 0 .. 3 { for index_poison in [false, true]! {
			lane := IntegerValue{value: 0x9e3779b97f4a7c15, poison: replacement == 1}
			updated := inserted_vector(source, count, IntegerValue{value: index, poison: index_poison}, lane, replacement == 2)!
			assert source == original
			for selected in 0 .. count {
				if index_poison || index >= u64(count) { assert updated.lanes[selected].poison && updated.undef & (u16(1) << u32(selected)) == 0 } else if selected == int(index) {
					assert updated.lanes[selected] == lane && (updated.undef & (u16(1) << u32(selected)) != 0) == (replacement == 2)
				} else { assert updated.lanes[selected] == source.lanes[selected] && (updated.undef & (u16(1) << u32(selected))) == (source.undef & (u16(1) << u32(selected))) }; checks++
			}
			// A later valid insertion repairs exactly one lane, even after a
			// whole-vector poison result. It cannot change the prior snapshot.
			saved := updated; repaired := inserted_vector(updated, count, IntegerValue{value: 0}, IntegerValue{value: 29}, false)!
			assert updated == saved && !repaired.lanes[0].poison && repaired.lanes[0].value == 29 && repaired.undef & 1 == 0
		} } }
	} }
	assert checks == 65280
	for count in [0, 17] { if _ := inserted_vector(ScalarVectorValue{}, count, IntegerValue{}, IntegerValue{}, false) { assert false, 'count guard' } }
	for lane in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { if _ := inserted_vector(ScalarVectorValue{}, 1, IntegerValue{}, lane, false) { assert false, 'scalar lane required' } }
	println('AIR-VECTOR-INSERT-STATES: ${checks} independent lane-state checks, counts 1..16, defined/poison/undef/mixed sources and replacement states, invalid/poison indices, repairs, immutable snapshots and scalar/count guards PASS')
}
