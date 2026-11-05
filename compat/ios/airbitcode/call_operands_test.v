// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

struct CallFixture {
mut:
	blocks []Block
	records []Record
	values []u64
	types []IRType
	refs []int
	functions []IRFunction
	scopes []IRConstantScope
	arguments []int
	layout string
}
fn call_fixture() CallFixture {
	mut f := CallFixture{
		blocks: [Block{parent: -1}, Block{id: 8, parent: 0}, Block{id: 12, parent: 1}]
		types: [IRType{kind: .void_t}, IRType{kind: .integer_t, bits: 32}, IRType{kind: .float_t}, IRType{kind: .pointer_t}, IRType{kind: .metadata_t},
			IRType{kind: .function_t, refs_count: 4}, IRType{kind: .function_t, refs_start: 4, refs_count: 2}, IRType{kind: .function_t, refs_start: 6, refs_count: 2},
			IRType{kind: .function_t, refs_start: 8, refs_count: 2, vararg: true}, IRType{kind: .pointer_t, refs_start: 10, refs_count: 1},
			IRType{kind: .function_t, refs_start: 11, refs_count: 2}]
		refs: [0, 3, 1, 2, 1, 1, 0, 1, 2, 1, 6, 0, 4]
		scopes: [IRConstantScope{active: true}, IRConstantScope{active: true, base_id: 8, arguments_count: 3}, IRConstantScope{}, IRConstantScope{}, IRConstantScope{}, IRConstantScope{}]
		arguments: [3, 1, 2]
	}
	f.records.flags |= .noslices; f.values.flags |= .noslices; f.types.flags |= .noslices; f.refs.flags |= .noslices
	for i, signature in [5, 6, 7, 8, 10] {
		f.add(1, 8, [u64(0), 1, u64(signature), 0, u64(i != 0), 0, 0, 0, 0, 0])
		f.functions << IRFunction{signature: signature, declaration: i != 0, record: i, body_block: if i == 0 { 2 } else { -1 }, basic_blocks: if i == 0 { 1 } else { 0 }}
	}
	f.add(2, 1, [u64(1)])
	f.add(2, 34, [u64(7), 32785, 6, 7, 2]) // %8: tail fastcc target(%6)
	f.add(2, 34, [u64(0), 32768, 7, 7, 1]) // void sink(%8), no value ID consumed.
	f.add(2, 34, [u64(0), 163840, 254, 8, 6, 3, 2]) // %9: fast float vararg(%6, %7)
	f.add(2, 34, [u64(0), 32768, 6, 5, 4]) // %10: indirect pointer %5, argument %6.
	f.add(2, 10, []u64{})
	return f
}
fn (mut f CallFixture) add(block int, code u64, values []u64) {
	f.records << Record{block: block, code: code, values_start: f.values.len, values_count: values.len}; f.values << values
}
fn (mut f CallFixture) replace(index int, code u64, values []u64) {
	f.records[index] = Record{...f.records[index], code: code, values_start: f.values.len, values_count: values.len}; f.values << values
}
fn (f CallFixture) stream() Stream { return Stream{f.blocks, f.records, f.values} }
fn (f CallFixture) ir() IRModule { return IRModule{data_layout: f.layout, types: f.types, references: f.refs, functions: f.functions} }
fn (f CallFixture) pools() IRConstantPools { return IRConstantPools{declarations: [0, 1, 2, 3, 4], scopes: f.scopes, arguments: f.arguments, module_values: 5} }
fn (f CallFixture) decode() !IRTypedProgram {
	pools := f.pools(); defer { unsafe { pools.declarations.free() } }
	bodies := f.ir().function_bodies(f.stream(), pools)!; defer { bodies.free() }
	return f.ir().typed_operands(f.stream(), pools, bodies)!
}
fn (f &CallFixture) free() {
	unsafe { f.blocks.free(); f.records.free(); f.values.free(); f.types.free(); f.refs.free(); f.functions.free(); f.scopes.free(); f.arguments.free() }
}
fn test_call_signatures_ids_flags_and_pointer_spaces() {
	for legacy in [false, true] {
		mut f := call_fixture(); defer { f.free() }
		f.layout = 'e-P3'
		if legacy { f.replace(1, 8, [u64(0), 1, 9, 0, 1, 0, 0, 0, 0, 0]) }
		p := f.decode()!; defer { p.free() }
		for op in p.instructions { assert op.status == .decoded }
		first := p.instructions[0]
		assert first.call_signature == 6 && first.callee_function == 1 && first.attribute_set == 7 && first.calling_convention == 8 && first.flags == 32785
		assert p.operands[first.operands_start].number == 1 && p.operands[first.operands_start + 1].number == 6
		pointer := p.types[p.operands[first.operands_start].type_index]
		assert pointer.kind == .pointer_t && pointer.address_space == 3 && pointer.refs_count == int(legacy)
		assert p.instructions[1].result_type == -1 && p.instructions[2].result_type == 2 && p.instructions[2].fast_math_flags == 254
		assert p.instructions[2].operands_count == 3 && p.operands[p.instructions[2].operands_start + 2].number == 7
		assert p.instructions[3].callee_function == -1 && p.operands[p.instructions[3].operands_start].number == 5
	}
	mut f := call_fixture(); defer { f.free() }
	f.replace(1, 8, [u64(0), 1, 6, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5])
	p := f.decode()!; defer { p.free() }
	assert p.types[p.operands[0].type_index].address_space == 5
	println('AIR-CALL-INDEX: direct/indirect/void/vararg calls, exact scoped IDs, typed/opaque declaration pointers, program/explicit address spaces, CC/attributes/tail/FMF PASS')
}
fn test_call_forward_types_and_incomplete_paths() {
	mut f := call_fixture(); defer { f.free() }
	f.replace(9, 34, [u64(0), 32768, 6, 0xffffffff, 3, 4])
	f.replace(10, 58, [u64(6)]); f.add(2, 10, []u64{})
	p := f.decode()!; defer { p.free() }
	assert p.instructions[3].status == .decoded && p.operands[p.instructions[3].operands_start].number == 11
	f.replace(6, 8, [u64(1)]) // Unknown result %8; sink argument and indirect callee depend on it.
	f.replace(9, 34, [u64(0), 32768, 6, 2, 4])
	q := f.decode()!; defer { q.free() }
	assert q.instructions[0].status == .opaque && q.instructions[1].status == .deferred && q.instructions[3].status == .deferred
	assert q.instructions[1].result_type == -1 && q.instructions[3].result_type == 1
	// A prefix before a call cannot disappear into a complete function index.
	f.replace(6, 55, [u64(0)]); f.replace(7, 34, [u64(0), 32768, 7, 7, 3])
	f.replace(8, 34, [u64(0), 163840, 254, 8, 5, 2, 1])
	f.replace(9, 34, [u64(0), 32768, 6, 4, 3])
	f.replace(10, 10, []u64{}); f.records.trim(11)
	r := f.decode()!; defer { r.free() }
	assert r.instructions[0].status == .opaque && r.instructions[0].result_type == -1
	f.records[6] = Record{block: 1, code: 99}
	f.replace(7, 34, [u64(0), 32768, 10, 4, 1]) // Metadata arguments remain opaque, not misread as value IDs.
	f.records.trim(8); f.add(2, 10, []u64{})
	s := f.decode()!; defer { s.free() }
	assert s.instructions[0].status == .opaque
	println('AIR-CALL-PARTIAL: forward callee claims, deferred callee/arguments, result seeds and bundled/metadata calls remain explicit PASS')
}
fn test_call_corruptions() {
	modes := ['short', 'implicit', 'signature-index', 'signature-kind', 'callee-kind', 'callee-ID', 'callee-width', 'arg-type', 'arg-ID', 'arg-missing', 'trailing', 'fmf-zero', 'fmf-width', 'fmf-integer', 'decl-AS', 'layout-P', 'layout-duplicate', 'forward-type', 'forward-mismatch']
	for mode in modes {
		mut f := call_fixture()
		match mode {
			'short' { f.replace(6, 34, [u64(0)]) }
			'implicit' { f.replace(6, 34, [u64(0), 0, 6, 7, 2]) }
			'signature-index' { f.replace(6, 34, [u64(0), 32768, 999, 7, 2]) }
			'signature-kind' { f.replace(6, 34, [u64(0), 32768, 1, 7, 2]) }
			'callee-kind' { f.replace(6, 34, [u64(0), 32768, 6, 2, 2]) }
			'callee-ID' { f.replace(6, 34, [u64(0), 32768, 6, 999, 2]) }
			'callee-width' { f.replace(6, 34, [u64(0), 32768, 6, 0x100000000, 2]) }
			'arg-type' { f.replace(6, 34, [u64(0), 32768, 6, 7, 1]) }
			'arg-ID' { f.replace(6, 34, [u64(0), 32768, 6, 7, 999]) }
			'arg-missing' { f.replace(6, 34, [u64(0), 32768, 6, 7]) }
			'trailing' { f.replace(6, 34, [u64(0), 32768, 6, 7, 2, 1]) }
			'fmf-zero' { f.replace(8, 34, [u64(0), 163840, 0, 8, 6, 3, 2]) }
			'fmf-width' { f.replace(8, 34, [u64(0), 163840, 256, 8, 6, 3, 2]) }
			'fmf-integer' { f.replace(6, 34, [u64(0), 163840, 254, 6, 7, 2]) }
			'decl-AS' { f.replace(1, 8, [u64(0), 1, 6, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x1000000]) }
			'layout-P' { f.layout = 'e-P' }
			'layout-duplicate' { f.layout = 'e-P1-P2' }
			'forward-type' { f.replace(9, 34, [u64(0), 32768, 6, 0xffffffff]) }
			'forward-mismatch' { f.replace(9, 34, [u64(0), 32768, 6, 0xffffffff, 9, 4]); f.replace(10, 58, [u64(6)]); f.add(2, 10, []u64{}) }
			else { panic('missing call corruption') }
		}
		if p := f.decode() { p.free(); assert false, mode }
		f.free()
	}
	println('AIR-CALL-REJECT: ${modes.len} directed header/signature/callee/argument/FMF/address-space/forward corruptions rejected')
}
fn test_call_mutations() {
	mut f := call_fixture(); defer { f.free() }
	mut count := 0
	for i in 0 .. f.values.len {
		for bit in [0, 1, 15, 31, 63] {
			old := f.values[i]; f.values[i] ^= u64(1) << bit
			if p := f.decode() { p.free() }
			f.values[i] = old; count++
		}
	}
	println('AIR-CALL-MUTATIONS: ${count} operand/header mutations handled with bounded cleanup PASS')
}
