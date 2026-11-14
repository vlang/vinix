// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Widened arithmetic is independent of the production overflow-bit formulas.
// The oracle is restricted to i1..i16 so all intermediates fit in i64.
fn vector_binary_expected(op u32, flags u64, bits u32, a u64, b u64) !(bool, u64) {
	modulus := i64(1) << bits; limit := modulus - 1; sign := modulus / 2
	x := i64(a & u64(limit)); y := i64(b & u64(limit))
	sx := if x >= sign { x - modulus } else { x }; sy := if y >= sign { y - modulus } else { y }
	if op in [u32(3), 4, 5, 6]! && (y == 0 || (op in [u32(4), 6]! && sx == -sign && sy == -1)) { return error('invalid division') }
	if op in [u32(7), 8, 9]! && y >= bits { return true, 0 }
	mut value := i64(0); mut signed_value := i64(0); mut poison := false
	match op {
		0 { value = x + y; signed_value = sx + sy }
		1 { value = x - y; signed_value = sx - sy }
		2 { value = x * y; signed_value = sx * sy }
		3 { value = x / y; poison = flags != 0 && value * y != x }
		4 { value = sx / sy; poison = flags != 0 && value * sy != sx }
		5 { value = x % y }
		6 { value = sx % sy }
		7 { value = x * (i64(1) << y); signed_value = sx * (i64(1) << y) }
		8 { value = x / (i64(1) << y); poison = flags != 0 && value * (i64(1) << y) != x }
		9 { value = sx >> y; poison = flags != 0 && value * (i64(1) << y) != sx }
		10 { value = x & y }
		11 { value = x | y; poison = flags != 0 && value != x + y }
		else { value = x ^ y }
	}
	if op in [u32(0), 1, 2, 7]! { poison = (flags & 1 != 0 && (value < 0 || value > limit)) || (flags & 2 != 0 && (signed_value < -sign || signed_value >= sign)) }
	return poison, u64(value) & u64(limit)
}
fn test_vector_integer_binary_values_flags_and_snapshots() {
	mut values := 0; mut rejected := 0; mut attempts := 0
	for bits in u32(1) .. 17 { for count in 1 .. 17 { for sample in 0 .. 8 {
		mut left := ScalarVectorValue{}; mut right := ScalarVectorValue{}
		words := [u64(0), 1, constant_mask(bits), u64(1) << (bits - 1), (u64(1) << (bits - 1)) - 1, 2, 3, 0xaaaaaaaaaaaaaaaa]!
		for lane in 0 .. count { left.lanes[lane] = IntegerValue{value: words[(sample + lane) % 8]}; right.lanes[lane] = IntegerValue{value: words[(sample / 2 + lane * 3) % 8]} }
		before_left := left; before_right := right
		for op in u32(0) .. 13 { for flags in u64(0) .. integer_binary_flag_mask(op) + 1 {
			attempts++
			mut invalid := false
			for lane in 0 .. count { if _, _ := vector_binary_expected(op, flags, bits, left.lanes[lane].value, right.lanes[lane].value) {} else { invalid = true } }
			if invalid { if _ := binary_vector(left, right, bits, count, op, flags) { assert false, 'invalid division accepted' }; rejected++; continue }
			result := binary_vector(left, right, bits, count, op, flags)!; assert result.undef == 0
			for lane in 0 .. count { poison, word := vector_binary_expected(op, flags, bits, left.lanes[lane].value, right.lanes[lane].value)!; assert result.lanes[lane].poison == poison && (poison || result.lanes[lane].value == word); values++ }
			frozen_vector(result, count)!; inserted_vector(result, count, IntegerValue{}, IntegerValue{value: 17}, false)!
			assert left == before_left && right == before_right
		} }
	} } }
	assert attempts == 61440 && values > 0 && rejected > 0
	println('AIR-VECTOR-BINARY-VALUES: ${values} independent widened i1-i16 lane checks and ${rejected} whole-vector division rejections; all counts 1..16, thirteen opcodes, thirty flag variants, masking, shifts and immutable sources PASS')
}
fn test_vector_integer_binary_lane_states_and_guards() {
	mut checks := 0
	for bits in u32(1) .. 65 { for count in 1 .. 17 { for lane in 0 .. count { for side in 0 .. 2 {
		mut left := ScalarVectorValue{}; mut right := ScalarVectorValue{}
		for i in 0 .. count { left.lanes[i] = IntegerValue{value: 0}; right.lanes[i] = IntegerValue{value: 1} }
		if side == 0 { left.lanes[lane] = IntegerValue{poison: true} } else { right.lanes[lane] = IntegerValue{poison: true} }
		for op in u32(0) .. 13 {
			if op in [u32(3), 4, 5, 6]! { if _ := binary_vector(left, right, bits, count, op, 0) { assert false, 'poison division/remainder' } }
			else { result := binary_vector(left, right, bits, count, op, 0)!; for i in 0 .. count { assert result.lanes[i].poison == (i == lane || (op in [u32(7), 8, 9]! && bits == 1)) } }; checks++
		}
		if side == 0 { left.undef = u16(1) << u32(lane) } else { right.undef = u16(1) << u32(lane) }
		for op in u32(0) .. 13 { if _ := binary_vector(left, right, bits, count, op, 0) { assert false, 'undef binary operand' }; checks++ }
	} } } }
	assert checks == 452608
	for count in [0, 17] { if _ := binary_vector(ScalarVectorValue{}, ScalarVectorValue{}, 32, count, 0, 0) { assert false, 'count guard' } }
	for bits in [u32(0), 65] { if _ := binary_vector(ScalarVectorValue{}, ScalarVectorValue{}, bits, 2, 0, 0) { assert false, 'width guard' } }
	for op in u32(0) .. 13 { if _ := binary_vector(ScalarVectorValue{}, ScalarVectorValue{}, 32, 2, op, 4) { assert false, 'flags guard' } }
	if _ := binary_vector(ScalarVectorValue{}, ScalarVectorValue{}, 32, 2, 13, 0) { assert false, 'opcode guard' }
	println('AIR-VECTOR-BINARY-STATES: ${checks} poison/undef controls across i1-i64 and all counts/lanes/operands/opcodes; localized poison, strict division and count/width/opcode/flag guards PASS')
}
