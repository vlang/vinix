// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_shuffle_lane_states_and_independent_snapshots() {
	mut checks := 0
	for count in 1 .. 17 { for size in 1 .. 17 {
		mut mask := []u32{len: size}
		for states in 0 .. 16 {
			mut left := ScalarVectorValue{}; mut right := ScalarVectorValue{}
			for lane in 0 .. count {
				for side in 0 .. 2 {
					state := if side == 0 { states / 4 } else { states % 4 }
					value := IntegerValue{value: u64(1 + side * count + lane) * 17, poison: state == 1 || (state == 3 && lane % 4 == 1)}
					undef := state == 2 || (state == 3 && lane % 4 == 2)
					if side == 0 { left.lanes[lane] = value; if undef { left.undef |= u16(1) << u32(lane) } } else { right.lanes[lane] = value; if undef { right.undef |= u16(1) << u32(lane) } }
				}
			}
			old_left := left; old_right := right
			for sample in 0 .. count * 2 + 1 {
				for lane in 0 .. size { selected := (sample + lane * 7) % (count * 2 + 1); mask[lane] = if selected == count * 2 { ~u32(0) } else { u32(selected) } }
				result := shuffled_vector(left, right, count, mask)!
				assert left == old_left && right == old_right
				for lane in 0 .. size {
					selected := (sample + lane * 7) % (count * 2 + 1)
					if selected == count * 2 { assert result.lanes[lane].poison && result.undef & (u16(1) << u32(lane)) == 0 } else {
						source := if selected < count { left } else { right }; i := selected % count
						assert result.lanes[lane] == source.lanes[i]
						assert (result.undef >> u32(lane)) & 1 == (source.undef >> u32(i)) & 1
					}; checks++
				}
			}
		}; unsafe { mask.free() }
	} }
	assert checks == 626688
	for count in [0, 17] { if _ := shuffled_vector(ScalarVectorValue{}, ScalarVectorValue{}, count, [u32(0)]) { assert false, 'input count guard' } }
	for mask in [[]u32{}, []u32{len: 17}, [u32(2)], [u32(0xfffffffe)]] { if _ := shuffled_vector(ScalarVectorValue{}, ScalarVectorValue{}, 1, mask) { assert false, 'mask guard' }; unsafe { mask.free() } }
	println('AIR-VECTOR-SHUFFLE-STATES: ${checks} independent lane-state checks, all input/output counts 1..16, both sources, poison/undef/mixed states, poison mask entries, immutable snapshots and count/range guards PASS')
}

fn test_shuffle_mask_tags_are_not_negative_integer_indexes() {
	p := IRTypedProgram{}
	pools := IRConstantPools{words: [u64(0xffffffff)]}; defer { pools.free() }
	for kind in [IRConstantKind.poison, .undef] { assert p.shuffle_constant_lane(Stream{}, pools, IRConstant{kind: kind}, 0, 2)! == ~u32(0) }
	if _ := p.shuffle_constant_lane(Stream{}, pools, IRConstant{kind: .data}, 0, 2) { assert false, 'negative integer cannot impersonate poison mask' }
	println('AIR-VECTOR-SHUFFLE-MASK: poison/legacy-undef tags distinguished from negative integer indexes PASS')
}
