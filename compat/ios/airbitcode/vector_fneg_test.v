// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_vector_fneg_exhaustive_half_bits() {
	for word in u64(0) .. 65536 {
		mut source := ScalarVectorValue{}
		source.lanes[0] = IntegerValue{value: word}
		before := source
		result := negated_vector(source, 16, 1)!
		assert !result.lanes[0].poison && result.undef == 0
		assert result.lanes[0].value % 32768 == word % 32768
		assert result.lanes[0].value / 32768 != word / 32768
		assert negated_vector(result, 16, 1)!.lanes[0].value == word
		assert source == before
	}
	println('AIR-VECTOR-FNEG-HALF: all 65,536 encodings preserve magnitude, flip sign, restore under double negation and retain source snapshots PASS')
}
fn test_vector_fneg_lanes_states_and_guards() {
	mut checks := 0
	for bits in [u32(16), 32]! { for count in 1 .. 17 { for target in 0 .. count {
		mut source := ScalarVectorValue{}
		for lane in 0 .. count { source.lanes[lane] = IntegerValue{value: (u64(lane + 1) * 0x9e3779b9) & constant_mask(bits), poison: lane == target} }
		before := source; result := negated_vector(source, bits, count)!
		for lane in 0 .. count {
			assert result.lanes[lane].poison == (lane == target)
			assert result.lanes[lane].value % (u64(1) << (bits - 1)) == source.lanes[lane].value % (u64(1) << (bits - 1))
			assert result.lanes[lane].value / (u64(1) << (bits - 1)) != source.lanes[lane].value / (u64(1) << (bits - 1))
			checks++
		}
		assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
		assert negated_vector(frozen_vector(source, count)!, bits, count)!.lanes[target].value == u64(1) << (bits - 1)
		assert source == before
		source.undef = u16(1) << u32(target)
		if _ := negated_vector(source, bits, count) { assert false, 'undef must reject before selection or freezing' }
		assert !negated_vector(frozen_vector(source, count)!, bits, count)!.lanes[target].poison
	} } }
	for bits in [u32(0), 1, 15, 17, 31, 33, 64]! { if _ := negated_vector(ScalarVectorValue{}, bits, 1) { assert false, 'width guard' } }
	for count in [0, 17] { if _ := negated_vector(ScalarVectorValue{}, 16, count) { assert false, 'count guard' } }
	for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := negated_vector(source, 32, 1) { assert false, 'scalar lane required' } }
	println('AIR-VECTOR-FNEG-STATES: ${checks} lane checks across both formats, every count/lane, localized poison, source/result freezing, strict undef and shape/tag guards PASS')
}
