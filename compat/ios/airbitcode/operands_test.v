// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

struct OperandFixture {
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
fn operand_fixture() OperandFixture {
	mut f := OperandFixture{
		blocks: [Block{parent: -1}, Block{id: 8, parent: 0}, Block{id: 12, parent: 1}]
		types: [IRType{kind: .void_t}, IRType{kind: .integer_t, bits: 32}, IRType{kind: .integer_t, bits: 64}, IRType{kind: .float_t}, IRType{kind: .integer_t, bits: 1},
			IRType{kind: .vector_t, count: 2, refs_count: 1}, IRType{kind: .function_t, refs_start: 1, refs_count: 6}]
		refs: [1, 1, 1, 1, 4, 3, 5]
		functions: [IRFunction{signature: 6, body_block: 2, basic_blocks: 3}]
		scopes: [IRConstantScope{active: true}, IRConstantScope{active: true, base_id: 6, count: 2, arguments_count: 5}]
		constants: [IRConstant{type_index: 1}, IRConstant{type_index: 2}]
		declarations: [0]
		arguments: [1, 1, 4, 3, 5]
	}
	f.records.flags |= .noslices; f.values.flags |= .noslices
	f.add(1, [u64(3)])
	f.add(2, [u64(7), 6, 0]) // %8 = add i32 arg0, arg1
	f.add(3, [u64(1), 2, 1]) // %9 = zext i32 %8 to i64
	f.add(28, [u64(2), 4, 32]) // %10 = icmp eq i32 %8, zero
	f.add(11, [u64(1), 2, 1])
	f.add(16, [u64(1), 6, 0, 3, 1]) // %11: backward %8 and signed forward %12
	f.add(2, [u64(1), 11, 0]) // %12 = add i32 %11, arg0
	f.add(11, [u64(1), 2, 3])
	f.add(10, [u64(1)])
	return f
}
fn (mut f OperandFixture) add(code u64, values []u64) {
	f.records << Record{block: 2, code: code, values_start: f.values.len, values_count: values.len}
	f.values << values
}
fn (mut f OperandFixture) replace(index int, code u64, values []u64) {
	f.records[index] = Record{...f.records[index], code: code, values_start: f.values.len, values_count: values.len}
	f.values << values
}
fn (f OperandFixture) stream() Stream { return Stream{f.blocks, f.records, f.values} }
fn (f OperandFixture) ir() IRModule { return IRModule{types: f.types, references: f.refs, functions: f.functions} }
fn (f OperandFixture) pools() IRConstantPools { return IRConstantPools{declarations: f.declarations, scopes: f.scopes, constants: f.constants, arguments: f.arguments, module_values: 1} }
fn (f &OperandFixture) free() {
	unsafe { for typ in f.types { typ.name.free() } }
	unsafe { f.blocks.free(); f.records.free(); f.values.free(); f.types.free(); f.refs.free(); f.functions.free(); f.scopes.free(); f.constants.free(); f.declarations.free(); f.arguments.free() }
}
fn test_typed_type_name_ownership() {
	mut f := operand_fixture(); defer { f.free() }
	f.types.flags |= .noslices
	named := IRType{kind: .struct_t, name: 'OwnedType'.clone()}
	unsafe { f.types.push_many(&named, 1) }
	p := f.decode()!
	assert unsafe { p.types.last().name.str == f.types.last().name.str }
	p.free()
	assert f.types.last().name == 'OwnedType'
	println('AIR-OPERANDS-OWNERSHIP: copied type arena borrows original names and frees only its owned arrays PASS')
}
fn (f OperandFixture) decode() !IRTypedProgram {
	bodies := f.ir().function_bodies(f.stream(), f.pools())!
	defer { bodies.free() }
	return f.ir().typed_operands(f.stream(), f.pools(), bodies)!
}
fn test_typed_core_ids_and_forward_phi() {
	f := operand_fixture(); defer { f.free() }
	bodies := f.ir().function_bodies(f.stream(), f.pools())!
	defer { bodies.free() }
	p := f.ir().typed_operands(f.stream(), f.pools(), bodies)!
	defer { p.free() }
	assert p.complete(bodies, 1) && !p.complete(bodies, 0) && !p.complete(bodies, 2)
	assert p.instructions.len == 8 && p.instructions[0].result_type == 1 && p.instructions[1].result_type == 2
	assert p.instructions[2].result_type == 4 && p.instructions[2].opcode == 32
	assert p.operands[0].number == 1 && p.operands[1].number == 2 && p.operands[2].number == 8
	phi := p.instructions[4]
	assert p.operands[phi.operands_start].number == 8 && p.operands[phi.operands_start + 1].number == 12
	assert p.targets[phi.targets_start..phi.targets_start + phi.targets_count] == [0, 1]
	assert p.instructions[1].opcode == 1 && p.instructions[7].operands_count == 1
	println('AIR-OPERANDS-CORE: arithmetic/casts/comparisons/branches/return, normalized IDs, signed forward PHI and completeness PASS')
}
fn test_synthetic_boolean_vectors_and_opaque_dependencies() {
	mut f := operand_fixture(); defer { f.free() }
	f.records.clear(); f.values.clear(); f.functions[0] = IRFunction{...f.functions[0], basic_blocks: 1}; f.refs[1] = 0
	f.add(1, [u64(1)]); f.add(28, [u64(3), 3, 32]); f.add(10, []u64{})
	p := f.decode()!
	assert p.instructions[0].status == .decoded
	text := p.type_text(f.ir(), p.instructions[0].result_type)!
	assert text == '<2 x i1>'
	unsafe { text.free() }; p.free()
	f.replace(1, 8, [u64(1)]) // Shuffle remains outside this profile.
	f.replace(2, 2, [u64(1), 1, 0])
	f.add(10, []u64{})
	q := f.decode()!
	assert q.instructions[0].status == .opaque && q.instructions[1].status == .deferred
	q.free()
	println('AIR-OPERANDS-PARTIAL: synthetic vector boolean type and explicit opaque/deferred dependencies PASS')
}
fn test_typed_operand_corruptions() {
	modes := ['id-width', 'id-range', 'binary-type', 'binary-op', 'binary-trailing', 'cast-truncated', 'cast-op', 'cast-type', 'cast-width',
		'predicate', 'rhs-type', 'return-type', 'phi-short', 'phi-type', 'phi-id', 'phi-block', 'phi-conflict', 'phi-flags', 'branch-type', 'forward-type-missing']
	for mode in modes {
		mut f := operand_fixture()
		match mode {
			'id-width' { f.replace(1, 2, [u64(0x100000000), 6, 0]) }
			'id-range' { f.replace(1, 2, [u64(999), 6, 0]) }
			'binary-type' { f.replace(1, 2, [u64(4), 4, 10]) } // FP and opcode
			'binary-op' { f.replace(1, 2, [u64(7), 6, 13]) }
			'binary-trailing' { f.replace(1, 2, [u64(7), 6, 0, 0, 0]) }
			'cast-truncated' { f.replace(2, 3, [u64(1), 2]) }
			'cast-op' { f.replace(2, 3, [u64(1), 2, 99]) }
			'cast-type' { f.replace(2, 3, [u64(1), 999, 1]) }
			'cast-width' { f.replace(2, 3, [u64(1), 1, 1]) }
			'predicate' { f.replace(3, 28, [u64(2), 4, 99]) }
			'rhs-type' { f.replace(1, 2, [u64(7), 1, 0]) } // i64 constant
			'return-type' { f.replace(8, 10, [u64(4)]) }
			'phi-short' { f.replace(5, 16, [u64(1)]) }
			'phi-type' { f.replace(5, 16, [u64(0), 6, 0]) }
			'phi-id' { f.replace(5, 16, [u64(1), 9999, 0]) }
			'phi-block' { f.replace(5, 16, [u64(1), 6, 3]) }
			'phi-conflict' { f.replace(5, 16, [u64(1), 6, 0, 3, 0]) }
			'phi-flags' { f.replace(5, 16, [u64(1), 6, 0, 1]) }
			'branch-type' { f.replace(4, 11, [u64(1), 2, 3]) } // i32 %8, not i1
			'forward-type-missing' { f.replace(1, 2, [u64(0xffffffff)]) }
			else { panic('missing operand corruption') }
		}
		if p := f.decode() { p.free(); assert false, mode }
		f.free()
	}
	println('AIR-OPERANDS-REJECT: ${modes.len} ID/type/opcode/arity/predicate/PHI/return corruptions rejected')
}
fn test_typed_operand_mutations() {
	mut f := operand_fixture(); defer { f.free() }
	mut count := 0
	for i in 0 .. f.values.len {
		for bit in [0, 1, 15, 31, 63] {
			old := f.values[i]; f.values[i] ^= u64(1) << bit
			if p := f.decode() { p.free() }
			f.values[i] = old; count++
		}
	}
	println('AIR-OPERANDS-MUTATIONS: ${count} scalar operand mutations handled with bounded cleanup PASS')
}
