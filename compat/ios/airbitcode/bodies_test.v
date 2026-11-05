// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Deliberate structural fixtures; instruction operand semantics are not executable.
struct BodyFixture {
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
}
fn body_fixture_base() BodyFixture {
	mut f := BodyFixture{
		blocks: [Block{parent: -1}, Block{id: 8, parent: 0}, Block{id: 12, parent: 1}, Block{id: 12, parent: 1}, Block{id: 15, parent: 2}]
		types: [IRType{kind: .void_t}, IRType{kind: .integer_t, bits: 32}, IRType{kind: .function_t, refs_count: 1}, IRType{kind: .function_t, refs_start: 1, refs_count: 2}]
		refs: [0, 1, 1]
		functions: [IRFunction{signature: 2, body_block: 2, basic_blocks: 1}, IRFunction{signature: 2, body_block: 3, basic_blocks: 1}]
		scopes: [IRConstantScope{active: true}, IRConstantScope{active: true, base_id: 3, count: 2, arguments_count: 1}, IRConstantScope{active: true, base_id: 3, first: 2, count: 2, arguments_start: 1, arguments_count: 1}]
		constants: [IRConstant{scope: 1, number: 3, type_index: 1}, IRConstant{scope: 1, number: 4, type_index: 1}, IRConstant{scope: 2, number: 3, type_index: 1}, IRConstant{scope: 2, number: 4, type_index: 1}]
		declarations: [0, 1]
		arguments: [1, 1]
	}
	f.records.flags |= .noslices; f.values.flags |= .noslices
	return f
}
fn (mut f BodyFixture) add(block int, code u64, values []u64) int {
	index := f.records.len
	f.records << Record{block: block, code: code, values_start: f.values.len, values_count: values.len}
	f.values << values
	return index
}
fn (f BodyFixture) stream() Stream { return Stream{f.blocks, f.records, f.values} }
fn (f BodyFixture) ir() IRModule { return IRModule{types: f.types, references: f.refs, functions: f.functions} }
fn (f BodyFixture) pools() IRConstantPools { return IRConstantPools{declarations: f.declarations, scopes: f.scopes, constants: f.constants, arguments: f.arguments, module_values: 2} }
fn (f &BodyFixture) free() {
	unsafe { f.blocks.free(); f.records.free(); f.values.free(); f.types.free(); f.refs.free(); f.functions.free(); f.scopes.free(); f.constants.free(); f.declarations.free(); f.arguments.free() }
}
fn body_fixture() BodyFixture {
	mut f := body_fixture_base()
	f.functions[0] = IRFunction{...f.functions[0], basic_blocks: 3}
	f.add(2, 1, [u64(3)])
	f.add(2, 2, [u64(1)])
	f.add(2, 35, [u64(1), 1, 1, 0]); f.add(2, 33, []u64{})
	f.add(2, 55, [u64(0)]); f.add(2, 34, [u64(0), 32768, 2, 1]) // void call
	f.add(2, 11, [u64(1)])
	f.add(4, 99, [u64(999)]) // Nested metadata cannot allocate instruction IDs.
	f.add(2, 16, [u64(1), 1, 0])
	f.add(2, 34, [u64(0), 163840, 254, 3, 1, 1]) // FMF then explicit result type
	f.add(2, 11, [u64(1), 2, 1])
	f.add(2, 10, []u64{})
	f.add(3, 1, [u64(1)]); f.add(3, 58, [u64(1)]); f.add(3, 10, []u64{})
	return f
}
fn body_reject(f BodyFixture) {
	if bodies := f.ir().function_bodies(f.stream(), f.pools()) { bodies.free(); assert false, 'accepted malformed body fixture' }
}
fn test_body_blocks_values_calls_and_scopes() {
	f := body_fixture(); defer { f.free() }
	bodies := f.ir().function_bodies(f.stream(), f.pools())!
	defer { bodies.free() }
	assert bodies.instructions.len == 9 && bodies.results.len == 4 && bodies.blocks.len == 4
	assert bodies.scopes[1].base_id == 5 && bodies.scopes[1].results_count == 3
	assert bodies.instructions[0].next_value == 5 && bodies.instructions[0].has_result
	assert bodies.instructions[1].next_value == 6 && !bodies.instructions[1].has_result && bodies.instructions[1].call_signature == 2
	assert bodies.instructions[3].next_value == 6 && bodies.instructions[4].next_value == 7
	assert bodies.instructions[4].call_signature == 3 && bodies.instructions[4].has_result
	assert bodies.blocks[0].first == 0 && bodies.blocks[0].count == 3 && bodies.blocks[1].count == 3 && bodies.blocks[2].count == 1
	first := bodies.lookup(f.pools(), 1, 5)!
	second := bodies.lookup(f.pools(), 2, 5)!
	assert first.kind == .instruction && first.instruction == 0 && second.instruction == 7
	assert bodies.lookup(f.pools(), 1, 3)!.pooled.kind == .constant
	assert bodies.lookup(f.pools(), 1, 2)!.pooled.kind == .argument
	assert bodies.lookup(f.pools(), 0, 1)!.pooled.kind == .declaration
	for scope in [-1, 0, 1, 2, 3] { if _ := bodies.lookup(f.pools(), scope, ~u64(0)) { assert false } }
	println('AIR-BODIES-INDEX: block boundaries, void/value/FMF calls, local ID reuse, pooled lookup and auxiliary records PASS')
}
fn test_body_corruptions() {
	modes := ['unknown', 'reserved', 'duplicate-declare', 'missing-declare', 'count-mismatch', 'missing-terminator', 'extra-instruction',
		'blob', 'empty-value', 'unreachable-arity', 'empty-void', 'branch-arity', 'branch-target', 'branch-target-two', 'late-phi',
		'empty-bundle', 'bundle-consumer', 'dangling-bundle', 'debug-first', 'debug-again', 'debug-short', 'call-header', 'call-flags',
		'implicit-call', 'call-type-index', 'call-type-kind', 'call-args', 'fmf-zero', 'fmf-missing', 'invoke-target', 'invoke-short',
		'callbr-target', 'callbr-count', 'catchswitch-short']
	for mode in modes {
		mut f := body_fixture()
		mut index := 1
		mut code := u64(2)
		mut values := []u64{}
		match mode {
			'unknown' { code = 999; values = [u64(1)] }
			'reserved' { code = 17 }
			'duplicate-declare' { code = 1; values = [u64(3)] }
			'missing-declare' { index = 0; code = 2; values = [u64(1)] }
			'count-mismatch' { index = 0; code = 1; values = [u64(4)] }
			'missing-terminator' { index = 11; code = 2; values = [u64(1)] }
			'extra-instruction' { f.add(2, 2, [u64(1)]); body_reject(f); f.free(); continue }
			'blob' { f.records[1] = Record{...f.records[1], has_blob: true}; body_reject(f); f.free(); continue }
			'empty-value' {}
			'unreachable-arity' { code = 15; values = [u64(1)] }
			'empty-void' { code = 44 }
			'branch-arity' { code = 11; values = [u64(0), 1] }
			'branch-target' { code = 11; values = [u64(3)] }
			'branch-target-two' { code = 11; values = [u64(0), 3, 1] }
			'late-phi' { index = 2; code = 16; values = [u64(1), 1, 0] }
			'empty-bundle' { code = 55 }
			'bundle-consumer' { index = 5; code = 2; values = [u64(1)] }
			'dangling-bundle' { f.add(2, 55, [u64(0)]); body_reject(f); f.free(); continue }
			'debug-first' { index = 0; code = 33 }
			'debug-again' { code = 33; values = [u64(1)] }
			'debug-short' { code = 35; values = [u64(1)] }
			'call-header' { code = 34; values = [u64(0)] }
			'call-flags' { code = 34; values = [u64(0), ~u64(0), 2, 1] }
			'implicit-call' { code = 34; values = [u64(0), 0, 2, 1] }
			'call-type-index' { code = 34; values = [u64(0), 32768, 999, 1] }
			'call-type-kind' { code = 34; values = [u64(0), 32768, 1, 1] }
			'call-args' { code = 34; values = [u64(0), 32768, 3, 1] }
			'fmf-zero' { code = 34; values = [u64(0), 163840, 0, 2, 1] }
			'fmf-missing' { code = 34; values = [u64(0), 163840] }
			'invoke-target' { code = 13; values = [u64(0), 8192, 1, 3, 2, 1] }
			'invoke-short' { code = 13; values = [u64(0), 8192, 0] }
			'callbr-target' { code = 57; values = [u64(0), 32768, 0, 1, 3, 2, 1] }
			'callbr-count' { code = 57; values = [u64(0), 32768, 0, ~u64(0)] }
			'catchswitch-short' { code = 52; values = [u64(0)] }
			else { panic('missing body corruption') }
		}
		f.records[index] = Record{...f.records[index], code: code, values_start: f.values.len, values_count: values.len}
		f.values << values
		body_reject(f); f.free(); unsafe { values.free() }
	}
	println('AIR-BODIES-REJECT: ${modes.len} directed opcode/block/call/prefix/PHI corruptions rejected')
}

fn test_body_terminator_results_and_scope_limits() {
	for code in [u64(13), 52, 57] {
		mut f := body_fixture_base(); defer { f.free() }
		f.add(2, 1, [u64(1)])
		values := if code == 13 { [u64(0), 8192, 0, 0, 3, 1, 1] } else if code == 57 { [u64(0), 32768, 0, 1, 0, 3, 1, 1] } else { [u64(0), 0] }
		f.add(2, code, values); unsafe { values.free() }
		f.add(3, 1, [u64(1)]); f.add(3, 15, []u64{})
		bodies := f.ir().function_bodies(f.stream(), f.pools())!
		assert bodies.instructions[0].terminator && bodies.instructions[0].has_result && bodies.results == [0]
		bodies.free()
	}
	mut f := body_fixture()
	f.functions[0] = IRFunction{...f.functions[0], basic_blocks: u32(max_body_blocks + 1)}
	body_reject(f); f.free()
	mut g := body_fixture()
	g.functions[0] = IRFunction{...g.functions[0], declaration: true}
	bodies := g.ir().function_bodies(g.stream(), g.pools())!
	if _ := bodies.lookup(g.pools(), 1, 0) { assert false }
	bodies.free(); g.free()
	println('AIR-BODIES-TERMINATORS: invoke/callbr/catchswitch results, block cap and declaration isolation PASS')
}
fn test_body_operand_mutations() {
	mut f := body_fixture(); defer { f.free() }
	mut count := 0
	for i in 0 .. f.values.len {
		for bit in [0, 1, 15, 31, 63] {
			old := f.values[i]; f.values[i] ^= u64(1) << bit
			if bodies := f.ir().function_bodies(f.stream(), f.pools()) { bodies.free() }
			f.values[i] = old; count++
		}
	}
	println('AIR-BODIES-MUTATIONS: ${count} operand mutations handled with bounded cleanup PASS')
}
