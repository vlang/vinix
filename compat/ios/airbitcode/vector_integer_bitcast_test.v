// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_integer_vector_bitcast_all_shapes_values_states_and_snapshots() {
	mut shapes := 0
	mut values := 0
	mut states := 0
	for source_bits in u32(1) .. 65 { for source_count in 1 .. 17 { for bits in u32(1) .. 65 {
		total := source_bits * u32(source_count)
		if total % bits != 0 || total / bits > 16 { continue }
		count := int(total / bits)
		shapes++
		for sample in 0 .. 8 {
			mut source := ScalarVectorValue{}
			for lane in 0 .. source_count {
				word := [u64(0), 1, ~u64(0), u64(1) << (source_bits - 1), (u64(1) << (source_bits - 1)) - 1, 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15, 0x0123456789abcdef]![(lane + sample) % 8]
				source.lanes[lane] = IntegerValue{value: word | ~constant_mask(source_bits)}
			}
			before := source
			result := bitcast_integer_vector(source, source_bits, source_count, bits, count)!
			assert result.undef == 0
			for lane in 0 .. count {
				mut expected := u64(0)
				for bit in u32(0) .. bits {
					position := u32(lane) * bits + bit
					expected |= ((source.lanes[position / source_bits].value >> (position % source_bits)) & 1) << bit
				}
				assert result.lanes[lane] == IntegerValue{value: expected}
				values++
			}
			roundtrip := bitcast_integer_vector(result, bits, count, source_bits, source_count)!
			for lane in 0 .. source_count { assert roundtrip.lanes[lane].value == source.lanes[lane].value & constant_mask(source_bits) }
			frozen_vector(result, count)!; inserted_vector(result, count, IntegerValue{}, IntegerValue{}, false)!
			assert source == before
		}
		for target in 0 .. source_count {
			mut source := ScalarVectorValue{}
			source.lanes[target] = IntegerValue{poison: true}
			result := bitcast_integer_vector(source, source_bits, source_count, bits, count)!
			frozen := frozen_vector(result, count)!
			for lane in 0 .. count {
				start := u32(lane) * bits; end := start + bits
				overlaps := start < u32(target + 1) * source_bits && end > u32(target) * source_bits
				assert result.lanes[lane].poison == overlaps
				assert frozen.lanes[lane] == IntegerValue{}
				states++
			}
			source.undef = u16(1) << u32(target)
			if _ := bitcast_integer_vector(source, source_bits, source_count, bits, count) { assert false, 'whole source undef rejection' }
			states++
		}
	} } }
	println('AIR-VECTOR-INTEGER-BITCAST: ${shapes} equal-total-width shapes, ${values} independent bit-stream values and round trips, ${states} poison-overlap/undef states; snapshots and freezes PASS')
}

fn test_integer_vector_bitcast_guards() {
	for shape in [[0, 1, 1, 1]!, [65, 1, 65, 1]!, [1, 0, 1, 0]!, [1, 17, 1, 17]!, [1, 1, 0, 1]!, [1, 1, 65, 1]!, [1, 1, 1, 0]!, [1, 1, 1, 17]!, [3, 3, 2, 4]!] {
		if _ := bitcast_integer_vector(ScalarVectorValue{}, u32(shape[0]), shape[1], u32(shape[2]), shape[3]) { assert false, 'invalid shape' }
	}
	for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] {
		mut source := ScalarVectorValue{}; source.lanes[1] = tag
		if _ := bitcast_integer_vector(source, 8, 2, 16, 1) { assert false, 'scalar source lanes' }
	}
	// Inactive storage does not belong to the source vector.
	mut source := ScalarVectorValue{undef: u16(0xfffc)}
	source.lanes[2] = IntegerValue{vector: true, poison: true}
	assert bitcast_integer_vector(source, 8, 2, 16, 1)!.lanes[0] == IntegerValue{}
	println('AIR-VECTOR-INTEGER-BITCAST-GUARDS: widths/counts/total width, lane tags and inactive storage PASS')
}
