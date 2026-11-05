// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

struct GlobalsFixture {
mut:
	data []u8
	blocks []Block
	records []Record
	values []u64
	types []IRType
	refs []int
	constants []IRConstant
	words []u64
}
fn globals_fixture() GlobalsFixture {
	mut f := GlobalsFixture{
		data: 'onetwofn'.bytes()
		blocks: [Block{parent: -1}, Block{id: 8, parent: 0}, Block{id: 23, parent: 0}]
		types: [IRType{kind: .integer_t, bits: 32}, IRType{kind: .array_t, count: 2, refs_count: 1}, IRType{kind: .pointer_t, address_space: 5, refs_start: 1, refs_count: 1}, IRType{kind: .void_t}]
		refs: [0, 1]
		constants: [IRConstant{kind: .integer, type_index: 0, bits: 32, words_count: 1}]
		words: [u64(0x12345678)]
	}
	f.records.flags |= .noslices; f.values.flags |= .noslices
	f.add(1, 7, [u64(0), 3, 0, 15, 5, 3, 3, 0]) // Global0, constant initializer ID4, AS3.
	f.add(1, 8, []u64{}) // Function1: preserves a hole in global declaration IDs.
	f.add(1, 7, [u64(3), 3, 2, 1, 0, 0, 0, 0]) // Global2: legacy typed-pointer external, AS5.
	f.add(1, 14, []u64{}) // Alias3 is not a variable descriptor.
	f.records << Record{block: 2, code: 1, has_blob: true, blob: Blob{size: 8}}
	return f
}
fn (mut f GlobalsFixture) add(block int, code u64, values []u64) { f.records << Record{block: block, code: code, values_start: f.values.len, values_count: values.len}; f.values << values }
fn (mut f GlobalsFixture) replace(index int, values []u64) { f.records[index] = Record{...f.records[index], values_start: f.values.len, values_count: values.len}; f.values << values }
fn (f GlobalsFixture) ir() IRModule { return IRModule{types: f.types, references: f.refs} }
fn (f GlobalsFixture) stream() Stream { return Stream{blocks: f.blocks, records: f.records, values: f.values} }
fn (f GlobalsFixture) pools() IRConstantPools { return IRConstantPools{declarations: [0, 1, 2, 3], constants: f.constants, words: f.words, scopes: [IRConstantScope{active: true}], module_values: 5} }
fn (f GlobalsFixture) decode() !IRGlobalVariables { p := f.pools(); defer { unsafe { p.declarations.free(); p.scopes.free() } }; return f.ir().global_variables(f.data, f.stream(), p)! }
fn (f &GlobalsFixture) free() { unsafe { f.data.free(); f.blocks.free(); f.records.free(); f.values.free(); f.types.free(); f.refs.free(); f.constants.free(); f.words.free() } }

fn test_global_storage_names_ids_initializers_and_images() {
	f := globals_fixture(); defer { f.free() }
	g := f.decode()!; defer { g.free() }
	assert g.entries.len == 2 && g.entries[0].number == 0 && g.entries[1].number == 2
	a := g.entries[0]; b := g.entries[1]
	assert a.name == 'one' && b.name == 'two' && a.name.str == f.data.data
	assert a.type_index == 0 && a.address_space == 3 && a.is_constant && a.alignment == 4 && a.linkage == 3
	assert a.has_initializer && a.initializer_number == 4 && a.initializer == 0
	assert !b.has_initializer && b.initializer == -1 && b.type_index == 1 && b.address_space == 5 && b.alignment == 0
	ir := f.ir(); layouts := ir.type_layouts()!; defer { layouts.free() }
	p := f.pools(); defer { unsafe { p.declarations.free(); p.scopes.free() } }
	image := g.initializer_image(ir, f.stream(), p, layouts, 0)!; defer { image.free() }
	assert image.status == .complete && image.bytes == [u8(0x78), 0x56, 0x34, 0x12] && image.value_mask == [u8(255), 255, 255, 255]
	external_image := g.initializer_image(ir, f.stream(), p, layouts, 1)!; defer { external_image.free() }
	assert external_image.status == .unavailable && external_image.reason == .relocation
	println('AIR-GLOBAL-STORAGE: borrowed names, declaration-ID holes, legacy/explicit storage types/address spaces, initializer IDs and literal/external templates PASS')
}
fn test_global_optional_flags_anonymous_and_direct_relocations() {
	mut f := globals_fixture(); defer { f.free() }
	f.types[2] = IRType{...f.types[2], address_space: 0}
	f.replace(0, [u64(0), 0, 0, 14, 5, 0, 0, 1, 2, 4, 1, 1])
	f.replace(2, [u64(0), 0, 2, 2, 2, 0, 0, 0]) // Explicit pointer storage, initializer is function declaration1.
	g := f.decode()!; defer { g.free() }
	assert g.entries[0].name == '' && g.entries[1].name == ''
	assert !g.entries[0].is_constant && g.entries[0].thread_local == 4 && g.entries[0].externally_initialized && g.entries[0].opaque_properties
	assert g.entries[1].has_initializer && g.entries[1].initializer == -1 && g.entries[1].initializer_number == 1
	assert g.entries[1].type_index == 2 && g.entries[1].address_space == 0
	println('AIR-GLOBAL-FLAGS: anonymous globals, TLS/external initialization, opaque properties and direct declaration relocation retained without allocation PASS')
}
fn test_global_storage_rejects_malformed_records() {
	modes := ['short', 'blob', 'scope', 'name-range', 'name-zero', 'duplicate', 'type', 'legacy', 'legacy-flags', 'legacy-reference', 'void', 'AS', 'initializer-ID', 'initializer-type', 'initializer-declaration-type', 'alignment', 'TLS', 'external-flag', 'linkage', 'strtab-extent']
	for mode in modes {
		mut f := globals_fixture(); defer { f.free() }
		match mode {
			'short' { f.replace(0, [u64(0), 3]) }
			'blob' { f.records[0] = Record{...f.records[0], has_blob: true} }
			'scope' { f.records[0] = Record{...f.records[0], block: 2} }
			'name-range' { f.replace(0, [u64(7), 3, 0, 15, 5, 3, 3, 0]) }
			'name-zero' { f.data[0] = 0 }
			'duplicate' { f.replace(2, [u64(0), 3, 2, 1, 0, 0, 0, 0]) }
			'type' { f.replace(0, [u64(0), 3, 99, 15, 5, 3, 3, 0]) }
			'legacy' { f.replace(0, [u64(0), 3, 0, 1, 5, 3, 3, 0]) }
			'legacy-flags' { f.replace(2, [u64(3), 3, 2, 4, 0, 0, 0, 0]) }
			'legacy-reference' { f.refs[1] = 99 }
			'void' { f.replace(0, [u64(0), 3, 3, 15, 0, 3, 3, 0]) }
			'AS' { f.replace(0, [u64(0), 3, 0, (u64(0x1000000) << 2) | 2, 5, 3, 3, 0]) }
			'initializer-ID' { f.replace(0, [u64(0), 3, 0, 15, 6, 3, 3, 0]) }
			'initializer-type' { f.replace(2, [u64(3), 3, 2, 1, 5, 0, 0, 0]) }
			'initializer-declaration-type' { f.replace(0, [u64(0), 3, 0, 15, 2, 3, 3, 0]) }
			'alignment' { f.replace(0, [u64(0), 3, 0, 15, 5, 3, 34, 0]) }
			'TLS' { f.replace(0, [u64(0), 3, 0, 15, 5, 3, 3, 0, 0, 5]) }
			'external-flag' { f.replace(0, [u64(0), 3, 0, 15, 5, 3, 3, 0, 0, 0, 0, 2]) }
			'linkage' { f.replace(0, [u64(0), 3, 0, 15, 5, u64(1) << 32, 3, 0]) }
			'strtab-extent' { f.records[4] = Record{...f.records[4], blob: Blob{offset: 1, size: 8}} }
			else {}
		}
		if g := f.decode() { g.free(); assert false, mode }
	}
	println('AIR-GLOBAL-STORAGE-REJECT: ${modes.len} record/name/type/initializer/alignment/flag corruptions rejected')
}
fn test_global_storage_mutations() {
	mut f := globals_fixture(); defer { f.free() }; mut count := 0
	for i in 0 .. f.values.len {
		for bit in [0, 1, 15, 31, 63] { old := f.values[i]; f.values[i] ^= u64(1) << bit; if g := f.decode() { g.free() }; f.values[i] = old; count++ }
	}
	for i in 0 .. f.data.len {
		for bit in [0, 1, 5, 7] { old := f.data[i]; f.data[i] ^= u8(1) << bit; if g := f.decode() { g.free() }; f.data[i] = old; count++ }
	}
	println('AIR-GLOBAL-STORAGE-MUTATIONS: ${count} record/name bit mutations handled with bounded cleanup PASS')
}
