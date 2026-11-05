// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

struct SwitchFixture {
mut:
	blocks []Block
	records []Record
	values []u64
	types []IRType
	refs []int
	functions []IRFunction
	scopes []IRConstantScope
	constants []IRConstant
	arguments []int
	words []u64
}
fn switch_fixture() SwitchFixture {
	mut f := SwitchFixture{
		blocks: [Block{parent: -1}, Block{id: 8, parent: 0}, Block{id: 12, parent: 1}]
		types: [IRType{kind: .void_t}, IRType{kind: .integer_t, bits: 32}, IRType{kind: .integer_t, bits: 128}, IRType{kind: .float_t}, IRType{kind: .function_t, refs_count: 3}]
		refs: [0, 1, 2]
		functions: [IRFunction{signature: 4, body_block: 2, basic_blocks: 4}]
		scopes: [IRConstantScope{active: true}, IRConstantScope{active: true, base_id: 2, count: 7, arguments_count: 2}]
		arguments: [1, 2]
		constants: [IRConstant{kind: .zero, type_index: 1, bits: 32},
			IRConstant{kind: .integer, type_index: 1, bits: 32, words_count: 1}, IRConstant{kind: .integer, type_index: 1, bits: 32, words_start: 1, words_count: 1},
			IRConstant{kind: .integer, type_index: 2, bits: 128, words_start: 2, words_count: 2}, IRConstant{kind: .integer, type_index: 2, bits: 128, words_start: 4, words_count: 2},
			IRConstant{kind: .zero, type_index: 2, bits: 128}, IRConstant{kind: .integer, type_index: 2, bits: 128, words_start: 6, words_count: 2}]
		words: [u64(0xffffffff), 0xffffffff, 1, 0, 1, 1, 1, 0]
	}
	f.records.flags |= .noslices; f.values.flags |= .noslices
	f.add(1, [u64(4)])
	f.add(12, [u64(1), 9, 3, 2, 1, 3, 2]) // Relative condition %0, absolute case IDs %2/%3.
	f.add(12, [u64(2), 8, 3, 5, 2, 6, 2, 7, 3]) // i128: 1, 2^64+1 and zero; shared destinations.
	f.add(10, []u64{}); f.add(10, []u64{})
	return f
}
fn (mut f SwitchFixture) add(code u64, values []u64) {
	f.records << Record{block: 2, code: code, values_start: f.values.len, values_count: values.len}; f.values << values
}
fn (mut f SwitchFixture) replace(index int, code u64, values []u64) {
	f.records[index] = Record{...f.records[index], code: code, values_start: f.values.len, values_count: values.len}; f.values << values
}
fn (f SwitchFixture) stream() Stream { return Stream{f.blocks, f.records, f.values} }
fn (f SwitchFixture) ir() IRModule { return IRModule{types: f.types, references: f.refs, functions: f.functions} }
fn (f SwitchFixture) pools() IRConstantPools { return IRConstantPools{scopes: f.scopes, constants: f.constants, arguments: f.arguments, words: f.words} }
fn (f SwitchFixture) decode() !IRTypedProgram {
	bodies := f.ir().function_bodies(f.stream(), f.pools())!; defer { bodies.free() }
	return f.ir().typed_operands(f.stream(), f.pools(), bodies)!
}
fn (f &SwitchFixture) free() {
	unsafe { f.blocks.free(); f.records.free(); f.values.free(); f.types.free(); f.refs.free(); f.functions.free(); f.scopes.free(); f.constants.free(); f.arguments.free(); f.words.free() }
}
fn test_switch_ids_targets_and_wide_cases() {
	mut f := switch_fixture(); defer { f.free() }
	p := f.decode()!; defer { p.free() }
	for op in p.instructions { assert op.status == .decoded }
	assert p.instructions[0].source_type == 1 && p.instructions[1].source_type == 2 && p.instructions[0].result_type == -1
	assert p.operands[0].number == 0 && p.operands[1].number == 2 && p.operands[2].number == 3 && p.operands[3].number == 1
	assert p.targets == [3, 1, 2, 3, 2, 2, 3]
	assert p.instructions[0].targets_count == 3 && p.instructions[1].operands_count == 4
	f.replace(1, 12, [u64(1), 9, 3])
	q := f.decode()!; defer { q.free() }
	assert q.instructions[0].operands_count == 1 && q.instructions[0].targets_count == 1
	println('AIR-SWITCH-INDEX: relative condition, absolute case IDs, default/case target ordering, i128 literals, shared targets and empty tables PASS')
}
fn test_switch_deferred_and_legacy_range() {
	mut f := switch_fixture(); defer { f.free() }
	f.records.clear(); f.values.clear()
	f.add(1, [u64(4)]); f.add(23, [u64(1)]); f.add(12, [u64(1), 1, 3, 2, 1, 3, 2])
	f.add(12, [u64(2), 9, 3, 5, 2]); f.add(10, []u64{}); f.add(10, []u64{})
	p := f.decode()!; defer { p.free() }
	assert p.instructions[0].status == .opaque && p.instructions[1].status == .deferred && p.instructions[1].source_type == 1
	f.replace(2, 12, [u64(0x4b5) << 16])
	q := f.decode()!; defer { q.free() }
	assert q.instructions[1].status == .opaque
	println('AIR-SWITCH-PARTIAL: unknown condition types defer; reverted range encoding remains explicitly opaque PASS')
}
fn test_switch_corruptions_and_work_budget() {
	modes := ['short', 'even', 'type-index', 'condition-kind', 'condition-type', 'condition-ID', 'default-target', 'case-target', 'case-ID', 'case-width', 'case-argument', 'case-type', 'case-poison', 'duplicate-ID', 'duplicate-value', 'duplicate-zero', 'duplicate-wide', 'limb-count']
	for mode in modes {
		mut f := switch_fixture()
		match mode {
			'short' { f.replace(1, 12, [u64(1)]) }
			'even' { f.replace(1, 12, [u64(1), 9, 3, 2]) }
			'type-index' { f.replace(1, 12, [u64(99), 9, 3]) }
			'condition-kind' { f.replace(1, 12, [u64(3), 9, 3]) }
			'condition-type' { f.arguments[0] = 3 }
			'condition-ID' { f.replace(1, 12, [u64(1), 999, 3]) }
			'default-target' { f.replace(1, 12, [u64(1), 9, 4]) }
			'case-target' { f.replace(1, 12, [u64(1), 9, 3, 2, 4]) }
			'case-ID' { f.replace(1, 12, [u64(1), 9, 3, 99, 1]) }
			'case-width' { f.replace(1, 12, [u64(1), 9, 3, 0x100000000, 1]) }
			'case-argument' { f.replace(1, 12, [u64(1), 9, 3, 0, 1]) }
			'case-type' { f.replace(1, 12, [u64(1), 9, 3, 5, 1]) }
			'case-poison' { f.constants[0] = IRConstant{...f.constants[0], kind: .poison} }
			'duplicate-ID' { f.replace(1, 12, [u64(1), 9, 3, 2, 1, 2, 2]) }
			'duplicate-value' { f.replace(1, 12, [u64(1), 9, 3, 3, 1, 4, 2]) }
			'duplicate-zero' { f.words[0] = 0 }
			'duplicate-wide' { f.replace(2, 12, [u64(2), 8, 3, 5, 1, 8, 2]) }
			'limb-count' { f.constants[3] = IRConstant{...f.constants[3], words_count: 1} }
			else { panic('missing switch corruption') }
		}
		if p := f.decode() { p.free(); assert false, mode }
		f.free()
	}
	f := switch_fixture(); defer { f.free() }
	bodies := f.ir().function_bodies(f.stream(), f.pools())!; defer { bodies.free() }
	mut b := OperandBuilder{ir: f.ir(), pools: f.pools(), bodies: bodies, switch_words: max_switch_words, p: IRTypedProgram{types: f.types.clone()}}
	defer { b.p.free() }
	if _ := b.switch_instruction(bodies.instructions[0], f.values[f.records[1].values_start..f.records[1].values_start + f.records[1].values_count]) { assert false, 'switch work budget' }
	println('AIR-SWITCH-REJECT: ${modes.len} directed record/type/ID/target/duplicate corruptions and cumulative word budget rejected')
}
fn test_switch_mutations() {
	mut f := switch_fixture(); defer { f.free() }
	mut count := 0
	for i in 0 .. f.values.len {
		for bit in [0, 1, 15, 31, 63] {
			old := f.values[i]; f.values[i] ^= u64(1) << bit
			if p := f.decode() { p.free() }
			f.values[i] = old; count++
		}
	}
	for i in 0 .. f.words.len {
		old := f.words[i]; f.words[i] ^= u64(1) << 31
		if p := f.decode() { p.free() }
		f.words[i] = old; count++
	}
	println('AIR-SWITCH-MUTATIONS: ${count} record/limb mutations handled with bounded cleanup PASS')
}
