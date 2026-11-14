// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_vector_freeze_defined_neighbors_idempotence_and_snapshots() {
	mut checks := 0
	for bits in u32(1) .. 65 { for count in 1 .. 17 { for pattern in [u64(0), 1, ~u64(0), u64(1) << (bits - 1), u64(0x7f800001), 0x7fc12345, 0x80007c01, 0x7e55]! { for state in 0 .. 4 {
		mut source := ScalarVectorValue{}
		for lane in 0 .. count {
			source.lanes[lane] = IntegerValue{value: (pattern ^ (u64(lane) * 17)) & constant_mask(bits), poison: state == 1 || (state == 3 && lane % 4 == 1)}
			if state == 2 || (state == 3 && lane % 4 == 2) { source.undef |= u16(1) << u32(lane) }
		}
		saved := source; frozen := frozen_vector(source, count)!
		assert source == saved && frozen.undef == 0 && frozen_vector(frozen, count)! == frozen
		for lane in 0 .. count { assert !frozen.lanes[lane].poison; assert frozen.lanes[lane] == if source.lanes[lane].poison || source.undef & (u16(1) << u32(lane)) != 0 { IntegerValue{} } else { source.lanes[lane] }; checks++ }
		updated := inserted_vector(frozen, count, IntegerValue{}, IntegerValue{value: 31}, false)!
		assert frozen_vector(source, count)! == frozen && updated.lanes[0].value == 31
	} } } }
	assert checks == 278528
	for count in [0, 17] { if _ := frozen_vector(ScalarVectorValue{}, count) { assert false, 'count guard' } }
	for value in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = value; if _ := frozen_vector(source, 1) { assert false, 'scalar lane guard' } }
	println('AIR-VECTOR-FREEZE-STATES: ${checks} independent lane-state checks, widths i1-i64, raw half/float patterns, all counts 1..16, defined neighbors, poison/undef/mixed choices, idempotence, immutable snapshots and count/scalar guards PASS')
}
