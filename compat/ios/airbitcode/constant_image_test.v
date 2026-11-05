// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

struct ImageFixture {
mut:
	types []IRType
	refs []int
	records []Record
	values []u64
	constants []IRConstant
	words []u64
}
fn image_fixture() ImageFixture {
	return ImageFixture{
		types: [IRType{kind: .integer_t, bits: 8}, IRType{kind: .integer_t, bits: 24}, IRType{kind: .integer_t, bits: 128},
			IRType{kind: .float_t}, IRType{kind: .half_t}, IRType{kind: .bfloat_t}, IRType{kind: .fp128_t},
			IRType{kind: .array_t, count: 2, refs_count: 1}, IRType{kind: .vector_t, count: 2, refs_count: 1},
			IRType{kind: .struct_t, refs_start: 1, refs_count: 2}, IRType{kind: .struct_t, packed: true, refs_start: 1, refs_count: 2},
			IRType{kind: .pointer_t}, IRType{kind: .array_t, count: 3, refs_start: 3, refs_count: 1},
			IRType{kind: .integer_t, bits: 1}, IRType{kind: .array_t, refs_count: 1}]
		refs: [1, 0, 1, 0]
		records: [Record{code: 7, values_count: 2}, Record{code: 7, values_start: 2, values_count: 2}]
		values: [u64(0), 1, 0, 1]
		constants: [IRConstant{kind: .integer, type_index: 0, bits: 8, words_count: 1},
			IRConstant{kind: .integer, type_index: 1, bits: 24, words_start: 1, words_count: 1},
			IRConstant{kind: .integer, type_index: 2, bits: 128, words_start: 2, words_count: 2},
			IRConstant{kind: .floating, type_index: 3, bits: 32, words_start: 4, words_count: 1},
			IRConstant{kind: .floating, type_index: 4, bits: 16, words_start: 5, words_count: 1},
			IRConstant{kind: .floating, type_index: 5, bits: 16, words_start: 6, words_count: 1},
			IRConstant{kind: .floating, type_index: 6, bits: 128, words_start: 7, words_count: 2},
			IRConstant{kind: .data, type_index: 7, words_start: 9, words_count: 2},
			IRConstant{kind: .integer, type_index: 8, bits: 24, splat: true, words_start: 1, words_count: 1},
			IRConstant{kind: .aggregate, type_index: 9}, IRConstant{kind: .aggregate, type_index: 10, record: 1},
			IRConstant{kind: .zero, type_index: 11}, IRConstant{kind: .string_data, type_index: 12, words_start: 11, words_count: 3},
			IRConstant{kind: .zero, type_index: 14}, IRConstant{kind: .integer, type_index: 13, bits: 1, words_count: 1}]
		words: [u64(0xab), 0x123456, 0x0123456789abcdef, 0xfedcba9876543210, 0x7fc01234, 0x8000, 0x7fc1,
			0x1122334455667788, 0x99aabbccddeeff00, 0x010203, 0xa0b0c0, 65, 0, 90]
	}
}
fn (f ImageFixture) ir(text string) IRModule { return IRModule{data_layout: text, types: f.types, references: f.refs} }
fn (f ImageFixture) pools() IRConstantPools { return IRConstantPools{constants: f.constants, words: f.words, module_values: u32(f.constants.len), scopes: [IRConstantScope{active: true}]} }
fn (f ImageFixture) stream() Stream { return Stream{records: f.records, values: f.values} }
fn (f &ImageFixture) free() { unsafe { f.types.free(); f.refs.free(); f.records.free(); f.values.free(); f.constants.free(); f.words.free() } }
fn test_constant_image_literal_bits_and_endianness() {
	f := image_fixture(); defer { f.free() }
	pools := f.pools(); defer { unsafe { pools.scopes.free() } }
	for text in ['e-i24:64', 'E-i24:64'] {
		ir := f.ir(text); layouts := ir.type_layouts()!; defer { layouts.free() }
		for index in 0 .. 7 {
			image := pools.constant_image(ir, f.stream(), layouts, index)!; defer { image.free() }
			assert image.status == .complete && image.reason == .none
			if index == 1 { assert image.value_mask == [u8(255), 255, 255, 0, 0, 0, 0, 0] }
			if index == 1 { assert image.bytes == (if text[0] == `e` { [u8(0x56), 0x34, 0x12, 0, 0, 0, 0, 0] } else { [u8(0x12), 0x34, 0x56, 0, 0, 0, 0, 0] }) }
			if index == 2 { assert image.bytes == (if text[0] == `e` { [u8(0xef), 0xcd, 0xab, 0x89, 0x67, 0x45, 0x23, 1, 0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe] } else { [u8(0xfe), 0xdc, 0xba, 0x98, 0x76, 0x54, 0x32, 0x10, 1, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef] }) }
			if index == 3 { assert image.bytes == (if text[0] == `e` { [u8(0x34), 0x12, 0xc0, 0x7f] } else { [u8(0x7f), 0xc0, 0x12, 0x34] }) }
			if index == 4 { assert image.bytes == (if text[0] == `e` { [u8(0), 0x80] } else { [u8(0x80), 0] }) }
			if index == 5 { assert image.bytes == (if text[0] == `e` { [u8(0xc1), 0x7f] } else { [u8(0x7f), 0xc1] }) }
			if index == 6 { assert image.bytes == (if text[0] == `e` { [u8(0x88), 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0, 0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa, 0x99] } else { [u8(0x99), 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88] }) }
		}
	}
	println('AIR-IMAGE-BITS: integer/FP bits, i24/i128, NaN payload, signed zero, bfloat/fp128 and both byte orders PASS')
}
fn test_constant_image_aggregate_padding_stride_strings_and_zero() {
	f := image_fixture(); defer { f.free() }
	pools := f.pools(); defer { unsafe { pools.scopes.free() } }
	ir := f.ir('e-i24:64'); l := ir.type_layouts()!; defer { l.free() }
	for index in 7 .. 15 {
		image := pools.constant_image(ir, f.stream(), l, index)!; defer { image.free() }
		if index == 7 { assert image.bytes == [u8(3), 2, 1, 0, 0, 0, 0, 0, 0xc0, 0xb0, 0xa0, 0, 0, 0, 0, 0] }
		if index == 8 { assert image.bytes == [u8(0x56), 0x34, 0x12, 0x56, 0x34, 0x12, 0, 0] && image.value_mask == [u8(255), 255, 255, 255, 255, 255, 0, 0] }
		if index == 9 { assert image.bytes.len == 16 && image.bytes[0] == 0xab && image.bytes[8] == 0x56 && image.bytes[7] == 0 && image.bytes[15] == 0 }
		if index == 10 { assert image.bytes == [u8(0xab), 0x56, 0x34, 0x12, 0, 0, 0, 0, 0] }
		if index == 11 { assert image.bytes == []u8{len: 8} }
		if index == 12 { assert image.bytes == [u8(65), 0, 90] }
		if index == 13 { assert image.status == .complete && image.bytes.len == 0 }
		if index == 14 { assert image.status == .unavailable && image.reason == .unsupported && image.bytes.len == 0 }
	}
	println('AIR-IMAGE-AGGREGATES: ordinary/packed fields, allocation padding, array/vector strides, splats, strings, null and empty arrays PASS')
}
fn test_constant_image_unavailable_and_malformed_inputs() {
	modes := ['undef', 'poison', 'opaque', 'nested-undef', 'relocation', 'record', 'reference', 'words', 'source', 'size', 'expansion']
	for mode in modes {
		mut f := image_fixture(); defer { f.free() }
		mut index := 9
		match mode {
			'undef', 'poison', 'opaque', 'nested-undef' { f.constants[0] = IRConstant{...f.constants[0], kind: if mode == 'poison' { .poison } else if mode == 'opaque' { .opaque } else { .undef }}; if mode != 'nested-undef' { index = 0 } }
			'relocation' { f.values[0] = 0 }
			'record' { f.records[0] = Record{code: 7, values_start: 99, values_count: 2} }
			'reference' { f.values[0] = 99 }
			'words' { f.constants[0] = IRConstant{...f.constants[0], words_start: 99} }
			'source' { f.constants[9] = IRConstant{...f.constants[9], type_index: 99} }
			'size' { f.types[14] = IRType{kind: .array_t, refs_count: 1, count: max_constant_image_bytes + 1}; index = 13 }
			'expansion' { f.types[8] = IRType{...f.types[8], count: max_constant_image_visits + 1}; index = 8 }
			else {}
		}
		p := f.pools(); defer { unsafe { p.scopes.free() } }
		ir := f.ir('e-i24:64'); l := ir.type_layouts()!; defer { l.free() }
		if mode == 'relocation' {
			declarations := [0]; defer { unsafe { declarations.free() } }
			view := IRConstantPools{...p, declarations: declarations}
			image := view.constant_image(ir, f.stream(), l, index)!; defer { image.free() }
			assert image.reason == .relocation && image.bytes.len == 0
		} else if mode in ['undef', 'poison', 'opaque', 'nested-undef'] {
			image := p.constant_image(ir, f.stream(), l, index)!; defer { image.free() }
			assert image.status == .unavailable && image.bytes.len == 0 && image.value_mask.len == 0
			assert image.reason == (if mode == 'poison' { IRImageReason.poison } else if mode == 'opaque' { IRImageReason.expression } else { IRImageReason.undef })
		} else if image := p.constant_image(ir, f.stream(), l, index) { image.free(); assert false, mode }
	}
	println('AIR-IMAGE-REJECT: ${modes.len} unavailable/malformed/byte-budget/expansion cases PASS; partial bytes never exposed')
}
fn test_constant_image_depth_budget() {
	mut f := ImageFixture{types: []IRType{len: 68}, refs: []int{len: 67}, records: []Record{len: 67}, values: []u64{len: 67}, constants: []IRConstant{len: 68}, words: [u64(1)]}
	defer { f.free() }
	f.types[0] = IRType{kind: .integer_t, bits: 8}; f.constants[0] = IRConstant{kind: .integer, bits: 8, words_count: 1}
	for i in 1 .. 68 {
		f.types[i] = IRType{kind: .struct_t, refs_start: i - 1, refs_count: 1}; f.refs[i - 1] = i - 1
		f.constants[i] = IRConstant{kind: .aggregate, type_index: i, record: i - 1}
		f.records[i - 1] = Record{code: 7, values_start: i - 1, values_count: 1}; f.values[i - 1] = u64(i - 1)
	}
	p := f.pools(); defer { unsafe { p.scopes.free() } }
	ir := f.ir('e'); l := ir.type_layouts()!; defer { l.free() }
	if image := p.constant_image(ir, f.stream(), l, 67) { image.free(); assert false, 'depth budget' }
	println('AIR-IMAGE-DEPTH: deep constant expansion rejected before exceeding the traversal budget PASS')
}
