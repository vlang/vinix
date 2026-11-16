// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn reduction_reference(op int, words [16]u64, bits u32, count int) u64 {
	mask := constant_mask(bits)
	mut result := if op == 1 { u64(1) } else if op == 2 { mask } else { u64(0) }
	if op >= 5 {
		mut chosen := 0
		for i in 1 .. count {
			key := (words[i] & mask) ^ if op < 7 { u64(1) << (bits - 1) } else { u64(0) }
			best := (words[chosen] & mask) ^ if op < 7 { u64(1) << (bits - 1) } else { u64(0) }
			if (op in [5,7] && key < best) || (op in [6,8] && key > best) { chosen = i }
		}
		return words[chosen] & mask
	}
	for i in 0 .. count { v := words[i] & mask; match op { 0 { result += v } 1 { result *= v } 2 { result &= v } 3 { result |= v } else { result ^= v } } }
	return result & mask
}
fn test_integer_vector_reduction_values() {
	mut checks := 0
	for op in 0 .. 9 { for bits in u32(1) .. 65 {
		for count in 1 .. 17 { for sample in 0 .. 8 {
			mut source := ScalarVectorValue{}; mut words := [16]u64{}
			for lane in 0 .. count {
				words[lane] = [u64(0), 1, ~u64(0), u64(1) << (bits - 1), (u64(1) << (bits - 1)) - 1, 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15, 0x0123456789abcdef]![(sample + lane) % 8] | ~constant_mask(bits)
				source.lanes[lane] = IntegerValue{value: words[lane]}
			}
			before := source
			assert reduced_integer_vector(unsafe { IntegerVectorReduction(op) }, source, bits, count)! == IntegerValue{value: reduction_reference(op, words, bits, count)}
			assert source == before; checks++
		} }
		if bits <= 8 {
			for pair in u64(0) .. u64(1) << (bits * 2) {
				mut source := ScalarVectorValue{}; mut words := [16]u64{}
				words[0] = pair & constant_mask(bits); words[1] = pair >> bits
				source.lanes[0] = IntegerValue{value: words[0]}; source.lanes[1] = IntegerValue{value: words[1]}
				assert reduced_integer_vector(unsafe { IntegerVectorReduction(op) }, source, bits, 2)!.value == reduction_reference(op, words, bits, 2); checks++
			}
		}
	} }
	assert checks == 860148
	println('AIR-VECTOR-REDUCTION-VALUES: ${checks} independent values, all nine operations/widths/counts, exhaustive i1..i8 pairs, upper-bit masks and snapshots PASS')
}
fn test_integer_vector_reduction_states() {
	mut checks := 0
	for op in 0 .. 9 { for bits in u32(1) .. 65 { for count in 1 .. 17 { for target in 0 .. count {
		mut source := ScalarVectorValue{}; source.lanes[target] = IntegerValue{poison: true}
		assert reduced_integer_vector(unsafe { IntegerVectorReduction(op) }, source, bits, count)!.poison; checks++
		source.undef = u16(1) << u32(target)
		if _ := reduced_integer_vector(unsafe { IntegerVectorReduction(op) }, source, bits, count) { assert false }; checks++
	} } } }
	for name in ['llvm.vector.reduce.add.v0i32','llvm.vector.reduce.mul.v01i8','llvm.vector.reduce.and.v17i32','llvm.vector.reduce.or.v2i0','llvm.vector.reduce.xor.v2i65','llvm.vector.reduce.smin.v2i032','llvm.vector.reduce.smax.v2f32','llvm.vector.reduce.umin.v2i32.spoof','llvm.vector.reduce.umax.nxv2i32','llvm.vector.reduce.fadd.v2f32','air.vector.reduce.add.v2i32','llvm.vector.reduce.add.v9999999999999i32'] { if _, _, _ := vector_reduction_name(name) { assert false, name } }
	for bits in [u32(0),65]! { if _ := reduced_integer_vector(.sum, ScalarVectorValue{}, bits, 1) { assert false } }
	for count in [0,17] { if _ := reduced_integer_vector(.sum, ScalarVectorValue{}, 32, count) { assert false } }
	for tag in [IntegerValue{aggregate:true}, IntegerValue{vector:true}] { mut source := ScalarVectorValue{}; source.lanes[0] = tag; if _ := reduced_integer_vector(.sum, source, 32, 1) { assert false } }
	assert checks == 156672
	println('AIR-VECTOR-REDUCTION-STATES: ${checks} all-lane poison/undef states and name/type/count/tag guards PASS')
}

fn test_integer_vector_reduction_undef_after_poison() {
	mut checks := 0
	for op in 0 .. 9 { for bits in u32(1) .. 65 { for count in 2 .. 17 {
		mut source := ScalarVectorValue{}
		source.lanes[0] = IntegerValue{poison: true}
		source.undef = u16(1) << u32(count - 1)
		if _ := reduced_integer_vector(unsafe { IntegerVectorReduction(op) }, source, bits, count) { assert false } else { assert err.msg().contains('undef') }
		checks++
	} } }
	assert checks == 8640
	println('AIR-VECTOR-REDUCTION-MIXED-STATES: ${checks} later undef lanes observed after earlier poison PASS')
}
