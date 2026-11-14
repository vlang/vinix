// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn cast_expected(op u32, flags u64, source u32, dest u32, word u64) IntegerValue {
	x := word & constant_mask(source)
	if op == 0 {
		unsigned_bad := x > constant_mask(dest)
		// Signed order is biased into unsigned order; test the mathematical
		// destination range independently of the production sign reconstruction.
		biased := x ^ (u64(1) << (source - 1))
		origin := u64(1) << (source - 1); radius := u64(1) << (dest - 1)
		signed_bad := biased < origin - radius || biased > origin + radius - 1
		if (flags & 1 != 0 && unsigned_bad) || (flags & 2 != 0 && signed_bad) { return IntegerValue{poison: true} }
		return IntegerValue{value: x & constant_mask(dest)}
	}
	negative := x >= u64(1) << (source - 1)
	if op == 1 && flags != 0 && negative { return IntegerValue{poison: true} }
	return IntegerValue{value: if op == 2 && negative { (constant_mask(dest) - constant_mask(source)) | x } else { x }}
}

fn test_integer_cast_promises_exhaustive_and_all_widths() {
	mut checks := 0
	for source in u32(2) .. 17 { for dest in u32(1) .. source { for flags in u64(0) .. 4 { for word in u64(0) .. u64(1) << source {
		assert scalar_integer_cast(0, flags, source, dest, IntegerValue{value: word})! == cast_expected(0, flags, source, dest, word); checks++
	} } } }
	for source in u32(1) .. 17 { for op in [u32(1), 2]! { for flags in u64(0) .. if op == 1 { u64(2) } else { u64(1) } { for word in u64(0) .. u64(1) << source {
		assert scalar_integer_cast(op, flags, source, 64, IntegerValue{value: word})! == cast_expected(op, flags, source, 64, word); checks++
	} } } }
	for source in u32(1) .. 65 { for dest in u32(1) .. 65 { if source == dest { continue }
		mask := constant_mask(source); sign := u64(1) << (source - 1); dm := constant_mask(dest)
		for op in if source > dest { [u32(0)] } else { [u32(1), 2] } { for flags in u64(0) .. if op == 0 { u64(4) } else if op == 1 { u64(2) } else { u64(1) } {
			for word in [u64(0), 1, 2, mask, mask - 1, sign, sign - 1, sign + 1, dm, dm + 1, dm - 1, dm >> 1, (dm >> 1) + 1, u64(0x5555555555555555), u64(0xaaaaaaaaaaaaaaaa), u64(0x9e3779b97f4a7c15)]! {
				assert scalar_integer_cast(op, flags, source, dest, IntegerValue{value: word})! == cast_expected(op, flags, source, dest, word); checks++
			}
			assert scalar_integer_cast(op, flags, source, dest, IntegerValue{poison: true})!.poison
		} }
	} }
	assert checks == 7959050
	println('AIR-INTEGER-CAST-FLAGS: ${checks} independent range/value checks, exhaustive short sources, all i1-i64 width pairs, NUW/NSW/both/NNeg, sign boundaries, unchanged unflagged resize and poison inputs PASS')
}

fn test_integer_cast_flag_and_profile_exclusions() {
	for op in u32(0) .. 14 { for flags in [u64(0), 1, 2, 3, 4, 8, 255, ~u64(0)]! {
		if op <= 2 && flags & ~scalar_cast_flag_mask(op) == 0 { continue }
		if _ := scalar_integer_cast(op, flags, 32, if op == 0 { u32(16) } else { u32(64) }, IntegerValue{}) { assert false, 'wrong-family/unknown cast flag' }
	} }
	for widths in [[u32(0), 8]!, [8, 0]!, [65, 8]!, [8, 65]!, [8, 8]!, [8, 16]!] { if _ := scalar_integer_cast(0, 3, widths[0], widths[1], IntegerValue{}) { assert false, 'trunc width/direction' } }
	for op in [u32(1), 2]! { for widths in [[u32(0), 8]!, [8, 0]!, [65, 8]!, [8, 65]!, [8, 8]!, [16, 8]!] { if _ := scalar_integer_cast(op, 0, widths[0], widths[1], IntegerValue{}) { assert false, 'extension width/direction' } } }
	mut p := IRTypedProgram{types: [IRType{kind: .integer_t, bits: 8}, IRType{kind: .integer_t, bits: 16}, IRType{kind: .float_t}], operands: [IRTypedOperand{type_index: 1}]}
	defer { p.free() }
	for flags in u64(0) .. 4 { p.scalar_cast_profile(IRTypedInstruction{opcode: 0, flags: flags, result_type: 0, operands_count: 1}, false)! }
	p.operands[0] = IRTypedOperand{type_index: 0}
	for flags in u64(0) .. 2 { p.scalar_cast_profile(IRTypedInstruction{opcode: 1, flags: flags, result_type: 1, operands_count: 1}, true)! }
	for op in [u32(2), 5, 6, 11]! { if _ := p.scalar_cast_profile(IRTypedInstruction{opcode: op, flags: 1, result_type: if op == 2 { 1 } else { 2 }, operands_count: 1}, true) { assert false, 'flags admitted on other casts' } }
	println('AIR-INTEGER-CAST-GUARDS: flag families, invalid widths/directions, scalar/mixed profiles and floating/sext/bitcast exclusions PASS')
}
