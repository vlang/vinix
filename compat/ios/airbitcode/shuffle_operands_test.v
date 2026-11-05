// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

struct ShuffleFixture {
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
fn shuffle_fixture() ShuffleFixture {
	mut f := ShuffleFixture{
		blocks: [Block{parent: -1}, Block{id: 8, parent: 0}, Block{id: 12, parent: 1}, Block{id: 11, parent: 2}]
		types: [IRType{kind: .void_t}, IRType{kind: .integer_t, bits: 32}, IRType{kind: .float_t},
			IRType{kind: .vector_t, count: 4, refs_count: 1}, IRType{kind: .vector_t, count: 2, refs_start: 1, refs_count: 1},
			IRType{kind: .vector_t, count: 2, refs_start: 2, refs_count: 1}, IRType{kind: .vector_t, count: 4, refs_start: 3, refs_count: 1},
			IRType{kind: .function_t, refs_start: 4, refs_count: 4}, IRType{kind: .integer_t, bits: 64},
			IRType{kind: .vector_t, count: 2, refs_start: 8, refs_count: 1}]
		refs: [2, 2, 1, 1, 0, 3, 3, 5, 8]
		functions: [IRFunction{signature: 7, body_block: 2, basic_blocks: 1}]
		scopes: [IRConstantScope{active: true}, IRConstantScope{active: true, base_id: 3, count: 6, arguments_count: 3}]
		arguments: [3, 3, 5]
		constants: [IRConstant{kind: .data, type_index: 5, scope: 1, number: 3, bits: 32, words_count: 2},
			IRConstant{kind: .poison, type_index: 5, scope: 1, number: 4}, IRConstant{kind: .zero, type_index: 5, scope: 1, number: 5},
			IRConstant{kind: .zero, type_index: 1, scope: 1, number: 6, bits: 32}, IRConstant{kind: .poison, type_index: 1, scope: 1, number: 7},
			IRConstant{kind: .aggregate, type_index: 5, scope: 1, number: 8, record: 0}]
		words: [u64(3), 4]
	}
	f.records.flags |= .noslices; f.values.flags |= .noslices
	f.add(3, 7, [u64(6), 7])
	f.add(2, 1, [u64(1)])
	f.add(2, 8, [u64(9), 8, 6]) // %9 = shuffle %0, %1, mask %3 -> <2 x float>.
	f.add(2, 8, [u64(10), 9, 6]) // %10: poison mask %4.
	f.add(2, 8, [u64(11), 10, 6]) // %11: zero mask %5.
	f.add(2, 8, [u64(12), 11, 4]) // %12: aggregate mask %8 (zero, poison).
	f.add(2, 10, []u64{})
	return f
}
fn (mut f ShuffleFixture) add(block int, code u64, values []u64) {
	f.records << Record{block: block, code: code, values_start: f.values.len, values_count: values.len}; f.values << values
}
fn (mut f ShuffleFixture) replace(index int, code u64, values []u64) {
	f.records[index] = Record{...f.records[index], code: code, values_start: f.values.len, values_count: values.len}; f.values << values
}
fn (f ShuffleFixture) stream() Stream { return Stream{f.blocks, f.records, f.values} }
fn (f ShuffleFixture) ir() IRModule { return IRModule{types: f.types, references: f.refs, functions: f.functions} }
fn (f ShuffleFixture) pools() IRConstantPools { return IRConstantPools{scopes: f.scopes, constants: f.constants, arguments: f.arguments, words: f.words} }
fn (f ShuffleFixture) decode() !IRTypedProgram {
	bodies := f.ir().function_bodies(f.stream(), f.pools())!; defer { bodies.free() }
	return f.ir().typed_operands(f.stream(), f.pools(), bodies)!
}
fn (f &ShuffleFixture) free() {
	unsafe { f.blocks.free(); f.records.free(); f.values.free(); f.types.free(); f.refs.free(); f.functions.free(); f.scopes.free(); f.constants.free(); f.arguments.free(); f.words.free() }
}
fn test_shuffle_masks_types_and_ids() {
	mut f := shuffle_fixture(); defer { f.free() }
	f.constants[4] = IRConstant{...f.constants[4], kind: .undef}
	p := f.decode()!; defer { p.free() }
	for op in p.instructions { assert op.status == .decoded }
	assert p.instructions[0].source_type == 3 && p.instructions[0].result_type == 4 && p.instructions[0].operands_count == 3
	assert p.operands[0].number == 0 && p.operands[1].number == 1 && p.operands[2].number == 3
	assert p.indices == [u32(3), 4, ~u32(0), ~u32(0), 0, 0, 0, ~u32(0)]
	assert p.instructions[3].indices_start == 6 && p.instructions[3].indices_count == 2
	println('AIR-SHUFFLE-INDEX: data/aggregate/zero/poison/undef masks, normalized lane sentinels, result width and exact scoped IDs PASS')
}
fn test_shuffle_scalable_forward_and_deferred() {
	mut f := shuffle_fixture(); defer { f.free() }
	f.replace(2, 8, [u64(0xffffffff), 3, 8, 6]) // Source %10 is defined later, with explicit type.
	f.constants[1] = IRConstant{...f.constants[1], type_index: 6}
	p := f.decode()!; defer { p.free() }
	assert p.instructions[0].status == .decoded && p.operands[0].number == 10 && p.instructions[1].result_type == 3
	f.replace(2, 23, [u64(1)])
	f.replace(3, 8, [u64(1), 9, 6]) // Source %9 remains unknown.
	f.constants[4] = IRConstant{...f.constants[4], kind: .opaque}
	q := f.decode()!; defer { q.free() }
	assert q.instructions[0].status == .opaque && q.instructions[1].status == .deferred
	assert q.instructions[3].status == .deferred && q.instructions[3].result_type == 4
	assert q.indices == [u32(0), 0] // Deferred aggregate expansion rolls back its first lane.
	f.replace(2, 8, [u64(9), 8, 6]); f.replace(3, 8, [u64(10), 9, 6]); f.replace(5, 8, [u64(12), 11, 7])
	for index in [3, 4, 5, 6] { f.types[index] = IRType{...f.types[index], scalable: true} }
	f.constants[0] = IRConstant{...f.constants[0], kind: .zero}
	r := f.decode()!; defer { r.free() }
	assert r.types[r.instructions[0].result_type].scalable && r.indices.len == 10
	println('AIR-SHUFFLE-PARTIAL: forward source types, opaque producers/mask expressions, rollback and scalable splat masks PASS')
}
fn test_shuffle_corruptions_and_budget() {
	modes := ['missing', 'trailing', 'source-scalar', 'rhs-type', 'mask-scalar', 'mask-i64', 'mask-dynamic', 'mask-range', 'mask-negative', 'mask-shape', 'mask-count', 'aggregate-count', 'aggregate-lane', 'forward-mismatch']
	for mode in modes {
		mut f := shuffle_fixture()
		match mode {
			'missing' { f.replace(2, 8, [u64(9), 8]) }
			'trailing' { f.replace(2, 8, [u64(9), 8, 6, 0]) }
			'source-scalar' { f.replace(2, 8, [u64(3), 8, 6]) }
			'rhs-type' { f.replace(2, 8, [u64(9), 7, 6]) }
			'mask-scalar' { f.replace(2, 8, [u64(9), 8, 3]) }
			'mask-i64' { f.constants[0] = IRConstant{...f.constants[0], type_index: 9} }
			'mask-dynamic' { f.replace(2, 8, [u64(9), 8, 7]) }
			'mask-range' { f.words[0] = 8 }
			'mask-negative' { f.words[0] = 0xffffffff }
			'mask-shape' { f.types[5] = IRType{...f.types[5], scalable: true} }
			'mask-count' { f.constants[0] = IRConstant{...f.constants[0], words_count: 1} }
			'aggregate-count' { f.replace(0, 7, [u64(6)]) }
			'aggregate-lane' { f.replace(0, 7, [u64(3), 7]) }
			'forward-mismatch' { f.replace(2, 8, [u64(0xffffffff), 3, 8, 6]) }
			else { panic('missing shuffle corruption') }
		}
		if p := f.decode() { p.free(); assert false, mode }
		f.free()
	}
	mut b := OperandBuilder{pools: IRConstantPools{constants: [IRConstant{kind: .zero}]}, p: IRTypedProgram{types: [IRType{kind: .vector_t, count: u64(max_typed_indices) + 1}]}}
	defer { unsafe { b.pools.constants.free() }; b.p.free() }
	if _ := b.shuffle_mask(0, 8, false) { assert false, 'mask expansion budget' }
	assert b.p.indices.len == 0
	println('AIR-SHUFFLE-REJECT: ${modes.len} directed record/type/lane/forward corruptions and expansion budget rejected')
}
fn test_shuffle_mutations() {
	mut f := shuffle_fixture(); defer { f.free() }
	mut count := 0
	for i in 0 .. f.values.len {
		for bit in [0, 1, 15, 31, 63] {
			old := f.values[i]; f.values[i] ^= u64(1) << bit
			if p := f.decode() { p.free() }
			f.values[i] = old; count++
		}
	}
	println('AIR-SHUFFLE-MUTATIONS: ${count} operand/aggregate mutations handled with bounded cleanup PASS')
}
