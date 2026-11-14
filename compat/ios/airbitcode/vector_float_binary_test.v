// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Exact small signed integers encoded independently of production conversion.
fn vector_float_integer(word i64, bits u32) u64 {
	if word == 0 { return 0 }
	magnitude := u64(if word < 0 { -word } else { word }); mut exponent := 0
	for magnitude >> u32(exponent + 1) != 0 { exponent++ }
	fraction := if bits == 16 { u32(10) } else { u32(23) }; bias := if bits == 16 { 15 } else { 127 }
	return (u64(word < 0) << (bits - 1)) | (u64(exponent + bias) << fraction) | ((magnitude - (u64(1) << u32(exponent))) << (fraction - u32(exponent)))
}
fn test_vector_float_binary_independent_exact_integer_values() {
	mut checks := 0
	for bits in [u32(16), 32]! { for count in 1 .. 17 { for sample in 0 .. 32 {
		mut left := ScalarVectorValue{}; mut right := ScalarVectorValue{}
		for lane in 0 .. count { left.lanes[lane] = IntegerValue{value: vector_float_integer(i64((sample + lane) % 32), bits)}; right.lanes[lane] = IntegerValue{value: vector_float_integer(i64((sample * 3 + lane) % 31 + 1), bits)} }
		a_before := left; b_before := right
		for op in [u32(0), 1, 2, 4, 6]! {
			result := floating_binary_vector(left, right, bits, count, op)!
			for lane in 0 .. count {
				a := i64((sample + lane) % 32); b := i64((sample * 3 + lane) % 31 + 1)
				if op == 4 && a % b != 0 { continue }
				word := match op { 0 { a + b } 1 { a - b } 2 { a * b } 4 { a / b } else { a % b } }
				assert !result.lanes[lane].poison && result.lanes[lane].value == vector_float_integer(word, bits)
				checks++
			}
			assert left == a_before && right == b_before
		}
	} } }
	println('AIR-VECTOR-FLOAT-BINARY-VALUES: ${checks} independent exact integer arithmetic lane checks across half/float, every count and all five operations; immutable sources PASS')
}
fn test_vector_float_binary_poison_undef_ieee_and_guards() {
	mut checks := 0
	for bits in [u32(16), 32]! { for count in 1 .. 17 { for target in 0 .. count { for side in 0 .. 2 {
		mut left := ScalarVectorValue{}; mut right := ScalarVectorValue{}
		for lane in 0 .. count { left.lanes[lane] = IntegerValue{value: vector_float_integer(7, bits)}; right.lanes[lane] = IntegerValue{value: vector_float_integer(2, bits)} }
		if side == 0 { left.lanes[target] = IntegerValue{poison: true} } else { right.lanes[target] = IntegerValue{poison: true} }
		for op in [u32(0), 1, 2, 4, 6]! {
			result := floating_binary_vector(left, right, bits, count, op)!
			for lane in 0 .. count { assert result.lanes[lane].poison == (lane == target); checks++ }
			assert frozen_vector(result, count)!.lanes[target] == IntegerValue{}
		}
		if side == 0 { left.undef = u16(1) << u32(target) } else { right.undef = u16(1) << u32(target) }
		for op in [u32(0), 1, 2, 4, 6]! { if _ := floating_binary_vector(left, right, bits, count, op) { assert false, 'undef arithmetic source' }; checks++ }
	} } } }
	for bits in [u32(16), 32]! {
		one := vector_float_integer(1, bits); infinity := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }; nan := if bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) }
		mut left := ScalarVectorValue{}; right := ScalarVectorValue{}
		left.lanes[0] = IntegerValue{value: one}
		assert floating_binary_vector(left, right, bits, 1, 4)!.lanes[0] == IntegerValue{value: infinity}
		assert floating_binary_vector(left, right, bits, 1, 6)!.lanes[0] == IntegerValue{value: nan}
		assert floating_binary_vector(right, right, bits, 1, 4)!.lanes[0] == IntegerValue{value: nan}
		left.lanes[0] = IntegerValue{value: infinity}
		assert floating_binary_vector(left, right, bits, 1, 2)!.lanes[0] == IntegerValue{value: nan}
	}
	for bits in [u32(0), 15, 17, 31, 33, 64]! { if _ := floating_binary_vector(ScalarVectorValue{}, ScalarVectorValue{}, bits, 1, 0) { assert false, 'format guard' } }
	for count in [0, 17] { if _ := floating_binary_vector(ScalarVectorValue{}, ScalarVectorValue{}, 16, count, 0) { assert false, 'count guard' } }
	for op in [u32(3), 5, 7, 8, 9, 10, 11, 12, 13]! { if _ := floating_binary_vector(ScalarVectorValue{}, ScalarVectorValue{}, 32, 1, op) { assert false, 'opcode guard' } }
	for side in 0 .. 2 { for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] { mut left := ScalarVectorValue{}; mut right := ScalarVectorValue{}; if side == 0 { left.lanes[0] = tag } else { right.lanes[0] = tag }; if _ := floating_binary_vector(left, right, 32, 1, 0) { assert false, 'scalar lanes required' } } }
	println('AIR-VECTOR-FLOAT-BINARY-STATES: ${checks} poison/undef lane controls across both formats/counts/lanes/operands/operations; IEEE zero divisors/invalid arithmetic, preferred NaNs and shape/tag/opcode guards PASS')
}
