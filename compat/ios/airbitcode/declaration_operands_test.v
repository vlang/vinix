// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

struct DeclarationFixture {
mut:
	blocks []Block
	records []Record
	values []u64
	types []IRType
	refs []int
	functions []IRFunction
	scopes []IRConstantScope
	constants []IRConstant
}
fn declaration_fixture() DeclarationFixture {
	mut f := DeclarationFixture{
		blocks: [Block{parent: -1}, Block{id: 8, parent: 0}, Block{id: 12, parent: 1}]
		types: [IRType{kind: .void_t}, IRType{kind: .integer_t, bits: 32}, IRType{kind: .float_t},
			IRType{kind: .pointer_t, address_space: 2, refs_count: 1}, IRType{kind: .pointer_t, address_space: 3, refs_start: 1, refs_count: 1},
			IRType{kind: .array_t, count: 4, refs_start: 2, refs_count: 1}, IRType{kind: .function_t, refs_start: 3, refs_count: 1},
			IRType{kind: .pointer_t, address_space: 2, refs_start: 4, refs_count: 1}]
		refs: [1, 5, 1, 1, 2]
		functions: [IRFunction{signature: 6, record: 3, body_block: 2, basic_blocks: 1}]
		scopes: [IRConstantScope{active: true, base_id: 4, count: 1}, IRConstantScope{active: true, base_id: 5}]
		constants: [IRConstant{kind: .zero, type_index: 1, bits: 32, number: 4}]
	}
	f.records.flags |= .noslices; f.values.flags |= .noslices
	f.add(1, 7, [u64(0), 1, 1, 10, 0, 0, 3, 0])
	f.add(1, 7, [u64(0), 1, 5, 14, 0, 0, 3, 0])
	f.add(1, 7, [u64(0), 1, 2, 10, 0, 0, 3, 0])
	f.add(1, 8, [u64(0), 1, 6, 0, 0, 0, 0, 0, 0, 0])
	f.add(2, 1, [u64(1)])
	f.add(2, 20, [u64(5), 1, 3, 0]) // %5: load global0.
	f.add(2, 43, [u64(0), 5, 5, 2, 1]) // %6: GEP global1, zero, %5.
	f.add(2, 20, [u64(1), 1, 3, 0]) // %7: load GEP.
	f.add(2, 44, [u64(8), 1, 3, 0]) // store %7 through global0.
	f.add(2, 20, [u64(6), 2, 3, 0]) // %8: load global2's float.
	f.add(2, 10, [u64(2)])
	return f
}
fn (mut f DeclarationFixture) add(block int, code u64, values []u64) {
	f.records << Record{block: block, code: code, values_start: f.values.len, values_count: values.len}; f.values << values
}
fn (mut f DeclarationFixture) replace(index int, values []u64) {
	f.records[index] = Record{...f.records[index], values_start: f.values.len, values_count: values.len}; f.values << values
}
fn (f DeclarationFixture) ir() IRModule { return IRModule{types: f.types, references: f.refs, functions: f.functions} }
fn (f DeclarationFixture) stream() Stream { return Stream{f.blocks, f.records, f.values} }
fn (f DeclarationFixture) pools() IRConstantPools { return IRConstantPools{declarations: [0, 1, 2, 3], scopes: f.scopes, constants: f.constants, module_values: 5} }
fn (f DeclarationFixture) decode() !IRTypedProgram {
	pools := f.pools(); defer { unsafe { pools.declarations.free() } }
	bodies := f.ir().function_bodies(f.stream(), pools)!; defer { bodies.free() }
	return f.ir().typed_operands(f.stream(), pools, bodies)!
}
fn (f &DeclarationFixture) free() {
	unsafe { f.blocks.free(); f.records.free(); f.values.free(); f.types.free(); f.refs.free(); f.functions.free(); f.scopes.free(); f.constants.free() }
}
fn test_global_declaration_pointer_profiles() {
	for mode in ['typed-explicit', 'typed-legacy', 'opaque', 'no-pointer-types'] {
		mut f := declaration_fixture(); defer { f.free() }
		if mode == 'typed-legacy' {
			f.replace(0, [u64(0), 1, 3, 0, 0, 0, 3, 0]); f.replace(1, [u64(0), 1, 4, 1, 0, 0, 3, 0]); f.replace(2, [u64(0), 1, 7, 0, 0, 0, 3, 0])
		}
		if mode == 'opaque' { for i in [3, 4, 7] { f.types[i] = IRType{kind: .pointer_t, address_space: if i == 3 { 2 } else if i == 4 { 3 } else { 4 }} } }
		if mode == 'no-pointer-types' { for i in [3, 4, 7] { f.types[i] = IRType{kind: .integer_t, bits: 16} } }
		p := f.decode()!; defer { p.free() }
		for op in p.instructions { assert op.status == .decoded }
		first := p.types[p.operands[0].type_index]
		assert first.kind == .pointer_t && first.address_space == 2 && first.refs_count == if mode.starts_with('typed') { 1 } else { 0 }
		assert p.instructions[0].result_type == 1 && p.operands[0].number == 0
		assert p.instructions[1].source_type == 5 && p.types[p.instructions[1].result_type].address_space == 3
		assert p.instructions[4].result_type == 2 && p.operands[p.instructions[4].operands_start].number == 2
	}
	println('AIR-GLOBAL-INDEX: explicit/legacy types, typed/opaque/no-pointer profiles, address spaces, exact IDs and dependent load/GEP/store types PASS')
}
fn test_unknown_global_declaration_kinds_defer() {
	for code in [u64(9), 14, 18] {
		mut f := declaration_fixture(); defer { f.free() }
		f.records[0] = Record{...f.records[0], code: code}
		p := f.decode()!; defer { p.free() }
		assert p.instructions[0].status == .deferred && p.instructions[0].result_type == 1
		assert p.instructions[3].status == .deferred
	}
	println('AIR-GLOBAL-PARTIAL: aliases/ifuncs remain untyped; dependent accesses defer with known load result preserved PASS')
}
fn test_global_declaration_corruptions() {
	modes := ['short', 'type-index', 'void-element', 'function-element', 'legacy-scalar', 'legacy-opaque', 'legacy-flags', 'address-space', 'mixed', 'blob']
	for mode in modes {
		mut f := declaration_fixture()
		match mode {
			'short' { f.replace(0, [u64(0), 1, 1, 10]) }
			'type-index' { f.replace(0, [u64(0), 1, 999, 10, 0, 0, 0, 0]) }
			'void-element' { f.replace(0, [u64(0), 1, 0, 10, 0, 0, 0, 0]) }
			'function-element' { f.replace(0, [u64(0), 1, 6, 10, 0, 0, 0, 0]) }
			'legacy-scalar' { f.replace(0, [u64(0), 1, 1, 0, 0, 0, 0, 0]) }
			'legacy-opaque' { f.replace(0, [u64(0), 1, 3, 0, 0, 0, 0, 0]); f.types[3] = IRType{kind: .pointer_t, address_space: 2} }
			'legacy-flags' { f.replace(0, [u64(0), 1, 3, 4, 0, 0, 0, 0]) }
			'address-space' { f.replace(0, [u64(0), 1, 1, (u64(0x1000000) << 2) | 2, 0, 0, 0, 0]) }
			'mixed' { f.types[7] = IRType{kind: .pointer_t} }
			'blob' { f.records[0] = Record{...f.records[0], has_blob: true} }
			else { panic('missing global declaration corruption') }
		}
		if p := f.decode() { p.free(); assert false, mode }
		f.free()
	}
	println('AIR-GLOBAL-REJECT: ${modes.len} header/type/flag/address-space/pointer-model/blob corruptions rejected')
}
fn test_global_declaration_mutations() {
	mut f := declaration_fixture(); defer { f.free() }
	mut count := 0
	for i in 0 .. f.values.len {
		for bit in [0, 1, 15, 31, 63] {
			old := f.values[i]; f.values[i] ^= u64(1) << bit
			if p := f.decode() { p.free() }
			f.values[i] = old; count++
		}
	}
	println('AIR-GLOBAL-MUTATIONS: ${count} declaration/operand mutations handled with bounded cleanup PASS')
}
