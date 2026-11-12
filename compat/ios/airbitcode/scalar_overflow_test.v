// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_scalar_overflow_pairs_against_widened_narrow_arithmetic() {
	ids := [ScalarIntrinsic.sadd_overflow, .uadd_overflow, .ssub_overflow, .usub_overflow, .smul_overflow, .umul_overflow]!
	mut count := 0
	for width in u32(1) .. 9 {
		full := constant_mask(width); limit := i64(1) << (width - 1)
		for x in u64(0) .. full + 1 { for y in u64(0) .. full + 1 { for i, id in ids {
			signed := i % 2 == 0
			a := if signed && x >= u64(limit) { i64(x) - 2 * limit } else { i64(x) }
			b := if signed && y >= u64(limit) { i64(y) - 2 * limit } else { i64(y) }
			exact := match i / 2 { 0 { a + b } 1 { a - b } else { a * b } }
			overflow := if signed { exact < -limit || exact >= limit } else { exact < 0 || exact > i64(full) }
			actual := scalar_integer_overflow_value(id, width, x | ~full, y | ~full)!
			assert actual.aggregate && !actual.poison && actual.value == u64(exact) & full && actual.overflow == overflow
			count++
		} } }
	}
	assert count == 524280
	println('AIR-OVERFLOW-NARROW: 524280 exact wrapped-value/overflow pairs against independent widened i1..i8 arithmetic PASS')
}

fn test_scalar_overflow_i64_limits_and_evaluator_guards() {
	ids := [ScalarIntrinsic.sadd_overflow, .uadd_overflow, .ssub_overflow, .usub_overflow, .smul_overflow, .umul_overflow]!
	rows := [
		[u64(0), 0x7fffffffffffffff, 1, 0x8000000000000000, 1]!,
		[u64(0), 0x8000000000000000, 0xffffffffffffffff, 0x7fffffffffffffff, 1]!,
		[u64(1), 0xffffffffffffffff, 1, 0, 1]!,
		[u64(1), 0x8000000000000000, 1, 0x8000000000000001, 0]!,
		[u64(2), 0x8000000000000000, 1, 0x7fffffffffffffff, 1]!,
		[u64(2), 0x7fffffffffffffff, 0xffffffffffffffff, 0x8000000000000000, 1]!,
		[u64(3), 0, 0xffffffffffffffff, 1, 1]!,
		[u64(3), 0xffffffffffffffff, 1, 0xfffffffffffffffe, 0]!,
		[u64(4), 0x8000000000000000, 0xffffffffffffffff, 0x8000000000000000, 1]!,
		[u64(4), 0x8000000000000000, 1, 0x8000000000000000, 0]!,
		[u64(5), 0xffffffffffffffff, 2, 0xfffffffffffffffe, 1]!,
		[u64(5), 0x8000000000000000, 1, 0x8000000000000000, 0]!,
	]!
	for row in rows { actual := scalar_integer_overflow_value(ids[int(row[0])], 64, row[1], row[2])!; assert actual.value == row[3] && actual.overflow == (row[4] != 0) && actual.aggregate && !actual.poison }
	for id in ids {
		assert scalar_intrinsic_arity(id) == 2 && scalar_integer_intrinsic(id)
		for width in [u32(0), 65]! { if _ := scalar_integer_overflow_value(id, width, 0, 0) { assert false, 'overflow width' } }
		if _ := scalar_intrinsic_value(id, 32, 0, 0) { assert false, 'pair through scalar evaluator' }
		if _ := scalar_integer_intrinsic_value(id, 32, 0) { assert false, 'binary pair through unary evaluator' }
	}
	if _ := scalar_integer_overflow_value(.clmul, 32, 0, 0) { assert false, 'non-overflow family' }
	for op in ['sadd', 'uadd', 'ssub', 'usub', 'smul', 'umul'] {
		for suffix in ['i0', 'i65', 'i01', 'i+8', 'i8.bad', 'v2i8'] {
			name := 'llvm.${op}.with.overflow.${suffix}'; defer { unsafe { name.free() } }
			if _ := scalar_intrinsic_name(name) { assert false, 'overflow overload spelling' }
		}
	}
	println('AIR-OVERFLOW-LIMITS: 12 i64 boundaries, six arity/name/width families and scalar/unary evaluator rejection PASS')
}

fn test_scalar_overflow_pair_shapes_and_runtime_tags() {
	assert sizeof(IntegerValue) == 16
	mut p := IRTypedProgram{types: [IRType{kind: .integer_t, bits: 32}, IRType{kind: .integer_t, bits: 1}, IRType{kind: .struct_t, refs_count: 2}], references: [0, 1]}
	defer { p.free() }
	assert p.scalar_overflow_element(2)! == 0
	original := p.types[2]
	for t in [IRType{...original, kind: .array_t}, IRType{...original, packed: true}, IRType{...original, name: 'named'}, IRType{...original, refs_count: 1}, IRType{...original, refs_start: -1}, IRType{...original, refs_start: 1}] {
		p.types[2] = t
		if _ := p.scalar_overflow_element(2) { assert false, 'invalid overflow pair layout' }
	}; p.types[2] = original
	p.references[1] = 0
	if _ := p.scalar_overflow_element(2) { assert false, 'overflow flag not i1' }
	println('AIR-OVERFLOW-SHAPES: literal unpacked {iN,i1} and invalid kind/packing/name/count/range/flag guards PASS')
}
