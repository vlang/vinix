// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

struct MemoryFixture {
mut:
	blocks []Block
	records []Record
	values []u64
	types []IRType
	refs []int
	functions []IRFunction
	scopes []IRConstantScope
	constants []IRConstant
	declarations []int
	arguments []int
	words []u64
	layout string = 'e-p:64:64-A0'
}
fn memory_fixture() MemoryFixture {
	mut f := MemoryFixture{
		blocks: [Block{parent: -1}, Block{id: 8, parent: 0}, Block{id: 12, parent: 1}]
		types: [IRType{kind: .void_t}, IRType{kind: .integer_t, bits: 32}, IRType{kind: .integer_t, bits: 64}, IRType{kind: .float_t},
			IRType{kind: .array_t, count: 4, refs_count: 1}, IRType{kind: .struct_t, refs_start: 1, refs_count: 2},
			IRType{kind: .pointer_t, address_space: 3, refs_start: 3, refs_count: 1}, IRType{kind: .pointer_t, address_space: 3, refs_start: 4, refs_count: 1},
			IRType{kind: .pointer_t, refs_start: 5, refs_count: 1}, IRType{kind: .function_t, refs_start: 6, refs_count: 4}]
		refs: [1, 1, 4, 5, 1, 1, 0, 6, 1, 5]
		functions: [IRFunction{signature: 9, body_block: 2, basic_blocks: 1}]
		scopes: [IRConstantScope{active: true}, IRConstantScope{active: true, base_id: 4, count: 3, arguments_count: 3}]
		constants: [IRConstant{kind: .zero, type_index: 1, bits: 32}, IRConstant{kind: .integer, type_index: 1, bits: 32, words_count: 1}, IRConstant{kind: .integer, type_index: 2, bits: 64, words_start: 1, words_count: 1}]
		declarations: [0]
		arguments: [6, 1, 5]
		words: [u64(1), 1]
	}
	f.records.flags |= .noslices; f.values.flags |= .noslices
	f.add(1, [u64(1)])
	f.add(19, [u64(1), 2, 6, 67]) // %7: explicit i32 alloca, absolute i64 count ID 6.
	f.add(43, [u64(1), 5, 7, 4, 3, 6]) // %8: pointer arg1 -> field1 array -> dynamic i32.
	f.add(20, [u64(1), 3, 1]) // %9: implicit typed-pointer load, volatile align 4.
	f.add(44, [u64(3), 1, 3, 0]) // Store %9 through alloca %7.
	f.add(27, [u64(7), 1, 1, 2]) // %10: insert %9 into argument3's field1/element2.
	f.add(26, [u64(1), 1, 2]) // %11: extract same field.
	f.add(10, []u64{})
	return f
}
fn (mut f MemoryFixture) add(code u64, values []u64) {
	f.records << Record{block: 2, code: code, values_start: f.values.len, values_count: values.len}; f.values << values
}
fn (mut f MemoryFixture) replace(index int, code u64, values []u64) {
	f.records[index] = Record{...f.records[index], code: code, values_start: f.values.len, values_count: values.len}; f.values << values
}
fn (f MemoryFixture) stream() Stream { return Stream{f.blocks, f.records, f.values} }
fn (f MemoryFixture) ir() IRModule { return IRModule{data_layout: f.layout, types: f.types, references: f.refs, functions: f.functions} }
fn (f MemoryFixture) pools() IRConstantPools { return IRConstantPools{declarations: f.declarations, scopes: f.scopes, constants: f.constants, arguments: f.arguments, words: f.words, module_values: 1} }
fn (f &MemoryFixture) free() {
	unsafe { f.blocks.free(); f.records.free(); f.values.free(); f.types.free(); f.refs.free(); f.functions.free(); f.scopes.free(); f.constants.free(); f.declarations.free(); f.arguments.free(); f.words.free() }
}
fn (f MemoryFixture) decode() !IRTypedProgram {
	bodies := f.ir().function_bodies(f.stream(), f.pools())!; defer { bodies.free() }
	return f.ir().typed_operands(f.stream(), f.pools(), bodies)!
}
fn test_memory_pointer_paths_alignment_and_aggregates() {
	for legacy in [false, true] {
		mut f := memory_fixture(); defer { f.free() }
		if legacy { f.replace(1, 19, [u64(8), 2, 6, 3]); f.replace(4, 24, [u64(3), 1, 3, 0]); f.replace(2, 30, [u64(7), 4, 3, 6]) }
		p := f.decode()!; defer { p.free() }
		for op in p.instructions { assert op.status == .decoded }
		assert p.instructions[0].result_type == 8 && p.instructions[0].source_type == 1 && p.instructions[0].alignment == 4
		assert p.operands[p.instructions[0].operands_start].number == 6
		assert p.instructions[1].result_type == 7 && p.instructions[1].source_type == 5 && p.instructions[1].flags == 1
		assert p.instructions[2].result_type == 1 && p.instructions[2].is_volatile && p.instructions[2].alignment == 4
		assert p.instructions[3].result_type == -1 && !p.instructions[3].is_volatile
		assert p.instructions[4].result_type == 5 && p.instructions[5].result_type == 1
		assert p.indices == [u32(1), 2, 1, 2]
	}
	println('AIR-MEMORY-INDEX: explicit/legacy alloca and memory forms, absolute counts, GEP fields/address spaces, volatility/alignment and aggregate paths PASS')
}
fn test_opaque_memory_and_alloca_address_spaces() {
	mut f := memory_fixture(); defer { f.free() }
	f.types[6] = IRType{kind: .pointer_t, address_space: 3}
	f.types[7] = IRType{kind: .pointer_t, address_space: 4}
	f.types[8] = IRType{kind: .pointer_t}
	f.layout = 'e-p:64:64-A5'
	f.replace(3, 20, [u64(1), 1, 0, 0]) // Explicit load type; ABI alignment unresolved.
	p := f.decode()!; defer { p.free() }
	assert p.types[p.instructions[0].result_type].address_space == 5
	assert p.types[p.instructions[0].result_type].refs_count == 0
	assert p.instructions[1].result_type == 6 && p.instructions[2].alignment == 0
	assert operand_alignment(33)! == u64(1) << 32
	if _ := operand_alignment(34) { assert false }
	println('AIR-MEMORY-OPAQUE: opaque pointers, explicit load types, alloca A5, unresolved ABI default and maximum explicit alignment PASS')
}
fn test_memory_record_corruptions() {
	modes := ['alloca-short', 'alloca-flags', 'alloca-count-type', 'alloca-count-ID', 'alloca-AS', 'alloca-align', 'gep-short', 'gep-base', 'gep-source', 'gep-field', 'gep-index-type',
		'load-arity', 'load-pointer', 'load-type', 'load-align', 'load-volatile', 'store-volatile', 'insert-type', 'path-empty', 'path-field', 'path-array', 'path-width', 'layout-empty', 'layout-AS', 'layout-duplicate', 'mixed-alloca']
	for mode in modes {
		mut f := memory_fixture()
		match mode {
			'alloca-short' { f.replace(1, 19, [u64(1)]) }
			'alloca-flags' { f.replace(1, 19, [u64(1), 2, 6, 0x800]) }
			'alloca-count-type' { f.replace(1, 19, [u64(1), 3, 6, 67]) }
			'alloca-count-ID' { f.replace(1, 19, [u64(1), 2, 99, 67]) }
			'alloca-AS' { f.replace(1, 19, [u64(1), 2, 6, 67, 0x1000000]) }
			'alloca-align' { f.replace(1, 19, [u64(1), 2, 6, 66 + 512]) }
			'gep-short' { f.replace(2, 43, [u64(1), 5]) }
			'gep-base' { f.replace(2, 43, [u64(1), 5, 6, 4]) }
			'gep-source' { f.replace(2, 43, [u64(1), 99, 7, 4]) }
			'gep-field' { f.words[0] = 2 }
			'gep-index-type' { f.arguments[1] = 3; f.refs[8] = 3 }
			'load-arity' { f.replace(3, 20, [u64(1), 1]) }
			'load-pointer' { f.replace(3, 20, [u64(7), 3, 0]) }
			'load-type' { f.replace(3, 20, [u64(1), 0, 3, 0]) }
			'load-align' { f.replace(3, 20, [u64(1), 34, 0]) }
			'load-volatile' { f.replace(3, 20, [u64(1), 3, 2]) }
			'store-volatile' { f.replace(4, 44, [u64(3), 1, 3, 2]) }
			'insert-type' { f.replace(5, 27, [u64(7), 7, 1, 2]) }
			'path-empty' { f.replace(6, 26, [u64(1)]) }
			'path-field' { f.replace(6, 26, [u64(1), 2]) }
			'path-array' { f.replace(6, 26, [u64(1), 1, 4]) }
			'path-width' { f.replace(6, 26, [u64(1), 0x100000000]) }
			'layout-empty' { f.layout = 'e-A' }
			'layout-AS' { f.layout = 'e-A16777216' }
			'layout-duplicate' { f.layout = 'e-A0-A1' }
			'mixed-alloca' { f.types[8] = IRType{kind: .pointer_t} }
			else { panic('missing memory corruption') }
		}
		if p := f.decode() { p.free(); assert false, mode }
		f.free()
	}
	println('AIR-MEMORY-REJECT: ${modes.len} alloca/GEP/load/store/aggregate/layout corruptions rejected')
}
fn test_memory_operand_mutations() {
	mut f := memory_fixture(); defer { f.free() }
	mut count := 0
	for i in 0 .. f.values.len {
		for bit in [0, 1, 15, 31, 63] {
			old := f.values[i]; f.values[i] ^= u64(1) << bit
			if p := f.decode() { p.free() }
			f.values[i] = old; count++
		}
	}
	println('AIR-MEMORY-MUTATIONS: ${count} operand mutations handled with bounded cleanup PASS')
}
