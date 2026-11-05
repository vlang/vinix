// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

struct GEPFixture {
mut:
	p IRTypedProgram
	pools IRConstantPools
	bodies IRFunctionBodies
	stream Stream
}
fn gep_fixture(source int, indexes []int) GEPFixture {
	mut f := GEPFixture{
		p: IRTypedProgram{
			types: [IRType{kind: .integer_t, bits: 8}, IRType{kind: .integer_t, bits: 24}, IRType{kind: .integer_t, bits: 32}, IRType{kind: .integer_t, bits: 64}, IRType{kind: .integer_t, bits: 128},
				IRType{kind: .array_t, count: 4, refs_count: 1}, IRType{kind: .vector_t, count: 3, refs_count: 1},
				IRType{kind: .struct_t, refs_start: 1, refs_count: 3}, IRType{kind: .struct_t, packed: true, refs_start: 1, refs_count: 3},
				IRType{kind: .pointer_t, address_space: 3}, IRType{kind: .pointer_t, address_space: 3}]
			references: [1, 0, 5, 6]
			instructions: [IRTypedInstruction{status: .decoded, result_type: 10, source_type: source, operands_count: indexes.len + 1, flags: 1}]
			operands: []IRTypedOperand{len: indexes.len + 1}
		}
		pools: IRConstantPools{module_values: 1, constants: [IRConstant{kind: .integer, bits: 32, type_index: 2, words_count: 1}], words: [u64(1)], scopes: [IRConstantScope{active: true}]}
		bodies: IRFunctionBodies{instructions: [IRInstruction{record: 0}]}
		stream: Stream{records: [Record{code: 43}]}
	}
	f.p.operands[0] = IRTypedOperand{type_index: 9}
	for i, typ in indexes { f.p.operands[i + 1] = IRTypedOperand{number: 0, type_index: typ} }
	return f
}
fn (f GEPFixture) layouts(text string) !IRTypeLayouts {
	return layout_types(text, f.p.types, f.p.references)!
}
fn (f GEPFixture) plan(l IRTypeLayouts) !IRGEPOffsetPlan { return f.p.gep_offset_plan(f.stream, f.pools, f.bodies, l, 0)! }
fn (f &GEPFixture) free() { f.p.free(); f.pools.free(); f.bodies.free(); f.stream.free() }

fn test_gep_nested_structure_offsets_and_modular_addressing() {
	f := gep_fixture(7, [0, 2, 3]); defer { f.free() }
	l := f.layouts('e-p3:64:64:64:16')!; defer { l.free() }
	p := f.plan(l)!; defer { p.free() }
	assert p.pointer_bits == 64 && p.index_bits == 16 && p.address_space == 3 && p.flags == 1
	assert p.constant_offset == 4 && p.terms == [IRGEPScale{1, 8, 48}, IRGEPScale{3, 64, 4}]
	assert p.offset([u64(255), 3])! == 65504 // -48 + 4 + 12.
	assert p.address(0x12340010, [u64(255), 3])! == 0x1234fff0
	assert p.offset([u64(0), 0x10001])! == 8 // Truncation to the pointer index width.
	assert p.offset([u64(0x101), 0])! == 52 // Ignore bits above the input's i8 width.
	println('AIR-GEP-NESTED: exact structure offsets/operand IDs, signed i8, truncation, 16-bit wrap and preserved high pointer bits PASS')
}
fn test_gep_packed_array_vector_and_wide_index_strides() {
	for source in [5, 6, 8] {
		indexes := if source == 8 { [3, 2, 4] } else { [3, 4] }; defer { unsafe { indexes.free() } }
		f := gep_fixture(source, indexes); defer { f.free() }
		l := f.layouts('e-p3:64:64-i24:64')!; defer { l.free() }
		p := f.plan(l)!; defer { p.free() }
		if source == 5 { assert p.terms[0].stride == 32 && p.terms[1].stride == 8 }
		if source == 6 { assert p.terms[0].stride == 16 && p.terms[1].stride == 3 }
		if source == 8 { assert p.constant_offset == 1 && p.terms[0].stride == 49 && p.terms[1].stride == 8 }
		assert p.terms[1].bits == 128
		values := [~u64(0), u64(2)]; defer { unsafe { values.free() } }
		assert p.offset(values)! == p.constant_offset - p.terms[0].stride + 2 * p.terms[1].stride
	}
	f := gep_fixture(5, []int{}); defer { f.free() }
	l := f.layouts('e-p3:32:32')!; defer { l.free() }
	p := f.plan(l)!; defer { p.free() }
	assert p.offset([]u64{})! == 0 && p.address(0x123456789, []u64{})! == 0x23456789
	println('AIR-GEP-STRIDES: packed fields, array allocation/vector store stride, low limbs of wide indexes, empty path and 32-bit pointers PASS')
}
fn test_gep_rejects_unavailable_layouts_and_bad_profiles() {
	modes := ['opaque', 'deferred', 'record', 'instruction', 'operands', 'source', 'base', 'result', 'index', 'field-type', 'field-range', 'field-constant', 'offset-range', 'unsized', 'width', 'vector-base', 'subbyte-vector', 'values']
	for mode in modes {
		mut f := gep_fixture(7, [3, 2, 3]); defer { f.free() }
		mut text := 'e-p3:64:64'
		match mode {
			'opaque' { f.p.instructions[0] = IRTypedInstruction{...f.p.instructions[0], status: .opaque} }
			'deferred' { f.p.instructions[0] = IRTypedInstruction{...f.p.instructions[0], status: .deferred} }
			'record' { f.stream.free(); f.stream = Stream{records: [Record{code: 20}]} }
			'instruction' { f.bodies.free(); f.bodies = IRFunctionBodies{instructions: [IRInstruction{record: 10}]} }
			'operands' { f.p.instructions[0] = IRTypedInstruction{...f.p.instructions[0], operands_count: 99} }
			'source' { f.p.instructions[0] = IRTypedInstruction{...f.p.instructions[0], source_type: -1} }
			'base', 'index', 'field-type' { i := if mode == 'base' { 0 } else if mode == 'index' { 1 } else { 2 }; f.p.operands[i] = IRTypedOperand{type_index: if mode in ['base', 'field-type'] { 3 } else { 9 }} }
			'result' { f.p.types[10] = IRType{kind: .pointer_t, address_space: 4} }
			'field-range' { old := f.pools.words; f.pools = IRConstantPools{...f.pools, words: [u64(3)]}; unsafe { old.free() } }
			'field-constant' { old := f.pools.constants; f.pools = IRConstantPools{...f.pools, constants: [IRConstant{...old[0], kind: .opaque}]}; unsafe { old.free() } }
			'unsized' { f.p.types[7] = IRType{kind: .opaque_t} }
			'width' { text = 'e-p3:128:128' }
			'vector-base' { f.p.types[9] = IRType{kind: .vector_t, count: 2, refs_start: 4, refs_count: 1}; f.p.references << 10 }
			'subbyte-vector' { f.p.types[1] = IRType{kind: .integer_t, bits: 1}; f.p.instructions[0] = IRTypedInstruction{...f.p.instructions[0], source_type: 6, operands_count: 3}; f.p.operands[2] = IRTypedOperand{type_index: 3} }
			else {}
		}
		l := f.layouts(text)!; defer { l.free() }
		if mode == 'offset-range' {
			view := IRTypeLayouts{...l, field_offsets: []u64{}}
			if p := f.plan(view) { p.free(); assert false, mode }
		} else if mode == 'values' {
			p := f.plan(l)!; defer { p.free() }
			if _ := p.offset([]u64{}) { assert false, mode }
		} else if p := f.plan(l) { p.free(); assert false, mode }
	}
	println('AIR-GEP-REJECT: ${modes.len} unavailable/malformed/profile/value-count cases rejected')
}
