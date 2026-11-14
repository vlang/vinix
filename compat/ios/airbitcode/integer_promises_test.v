// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn promise_predicate(op u32, bits u32, x u64, y u64) bool {
	// Compare signs first, then magnitudes; do not use production sign-biasing.
	sign := u64(1) << (bits - 1); nx := x >= sign; ny := y >= sign
	less_signed := if nx != ny { nx } else { x < y }
	return match op { 32 { x == y } 33 { x != y } 34 { x > y } 35 { x >= y } 36 { x < y } 37 { x <= y } 38 { !less_signed && x != y } 39 { !less_signed } 40 { less_signed } else { less_signed || x == y } }
}
fn test_integer_bit_sign_promises_exhaustive_and_wide() {
	mut checks := 0
	for bits in u32(1) .. 9 { for x in u64(0) .. u64(1) << bits { for y in u64(0) .. u64(1) << bits {
		// A carry into any position makes unsigned addition differ from OR.
		bad_or := x + y != x | y
		actual := integer_binary_flags(11, 1, bits, IntegerValue{value: x}, IntegerValue{value: y})!
		assert actual.poison == bad_or && (actual.poison || actual.value == x + y); checks++
		for op in u32(32) .. 42 {
			bad_sign := (x >= u64(1) << (bits - 1)) != (y >= u64(1) << (bits - 1))
			v := integer_compare_flags(op, 1, bits, IntegerValue{value: x}, IntegerValue{value: y})!
			assert v.poison == bad_sign && (v.poison || v.value == u64(promise_predicate(op, bits, x, y))); checks++
		}
	} } }
	for bits in u32(1) .. 65 {
		mask := constant_mask(bits); sign := u64(1) << (bits - 1)
		for a in [u64(0), 1, mask, mask - 1, sign, sign - 1, sign + 1, 0x5555555555555555, 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15]! { for b in [u64(0), 1, mask, mask - 1, sign, sign - 1, sign + 1, 0x5555555555555555, 0xaaaaaaaaaaaaaaaa, 0xfedcba9876543210]! {
			x := a & mask; y := b & mask
			mut overlap := false; for bit in u32(0) .. bits { if (x >> bit) % 2 == 1 && (y >> bit) % 2 == 1 { overlap = true } }
			v := integer_binary_flags(11, 1, bits, IntegerValue{value: a}, IntegerValue{value: b})!
			assert v.poison == overlap && (v.poison || v.value == x | y); checks++
			assert integer_binary_flags(11, 0, bits, IntegerValue{value: a}, IntegerValue{value: b})!.value == x | y
			for op in u32(32) .. 42 { for flags in [u64(0), 1]! {
				result := integer_compare_flags(op, flags, bits, IntegerValue{value: a}, IntegerValue{value: b})!
				assert result.poison == (flags != 0 && (x >= sign) != (y >= sign)) && (result.poison || result.value == u64(promise_predicate(op, bits, x, y))); checks++
			} }
		} }
		for position in 0 .. 2 { a := IntegerValue{value: 1, poison: position == 0}; b := IntegerValue{poison: position == 1}; assert integer_binary_flags(11, 1, bits, a, b)!.poison; for op in u32(32) .. 42 { assert integer_compare_flags(op, 1, bits, a, b)!.poison } }
	}
	assert checks == 1095580
	println('AIR-INTEGER-BIT-SIGN-PROMISES: ${checks} independent checks, exhaustive i1-i8 pairs and all i1-i64 boundary/pattern pairs, OR disjoint, all ten ICMP samesign predicates, masking, unchanged unflagged results and poison inputs PASS')
}
fn test_integer_bit_sign_promise_guards() {
	for flags in [u64(2), 3, 4, 8, ~u64(0)]! {
		if _ := integer_binary_flags(11, flags, 32, IntegerValue{}, IntegerValue{}) { assert false, 'wrong OR flag' }
		if _ := integer_compare_flags(32, flags, 32, IntegerValue{}, IntegerValue{}) { assert false, 'unknown comparison flag' }
	}
	for op in [u32(10), 12]! { if _ := integer_binary_flags(op, 1, 32, IntegerValue{}, IntegerValue{}) { assert false, 'flags on AND/XOR' } }
	for bits in [u32(0), 65]! { if _ := integer_compare_flags(32, 1, bits, IntegerValue{}, IntegerValue{}) { assert false, 'comparison width' } }
	for op in [u32(0), 31, 42]! { if _ := integer_compare_flags(op, 1, 32, IntegerValue{}, IntegerValue{}) { assert false, 'comparison predicate' } }
	mut p := IRTypedProgram{types: [IRType{kind: .integer_t, bits: 8}, IRType{kind: .float_t}, IRType{kind: .pointer_t}, IRType{kind: .vector_t}], operands: [IRTypedOperand{type_index: 0}, IRTypedOperand{type_index: 0}]}; defer { p.free() }
	op := IRTypedInstruction{opcode: 32, operands_count: 2}; assert p.integer_compare_flag_mask(op) == 1
	for typ in [-1, 1, 2, 3, 4] { p.operands[0] = IRTypedOperand{type_index: typ}; assert p.integer_compare_flag_mask(op) == 0 }
	p.operands[0] = IRTypedOperand{type_index: 0}
	for changed in [IRTypedInstruction{...op, operands_start: -1}, IRTypedInstruction{...op, operands_start: 2}, IRTypedInstruction{...op, operands_count: 0}, IRTypedInstruction{...op, opcode: 15}] { assert p.integer_compare_flag_mask(changed) == 0 }
	println('AIR-INTEGER-BIT-SIGN-GUARDS: unknown/wrong-family flags, widths/predicates and scalar integer-only comparison admission PASS')
}
