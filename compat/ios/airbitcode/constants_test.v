// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Deliberate semantic indexes; encoded-bitcode coverage uses independent LLVM
// assembly and real native AIR in air-constants-inspect.v.
struct ConstantFixture {
mut:
	blocks []Block
	records []Record
	values []u64
	ir IRModule
}
fn (mut f ConstantFixture) add(block int, code u64, values []u64) {
	f.records << Record{block: block, code: code, values_start: f.values.len, values_count: values.len}
	f.values << values
}
fn (f ConstantFixture) stream() Stream { return Stream{f.blocks, f.records, f.values} }
fn (mut f ConstantFixture) free() { f.ir.free(); unsafe { f.blocks.free(); f.records.free(); f.values.free() } }
fn (f ConstantFixture) find(block int, code u64, occurrence int) int {
	mut seen := 0
	for i, record in f.records {
		if record.block == block && record.code == code {
			if seen == occurrence { return i }
			seen++
		}
	}
	panic('missing constant fixture record')
}
fn (mut f ConstantFixture) set(block int, code u64, occurrence int, operand int, value u64) {
	record := f.records[f.find(block, code, occurrence)]
	f.values[record.values_start + operand] = value
}
fn constant_fixture() ConstantFixture {
	mut f := ConstantFixture{
		blocks: [Block{id: ~u64(0), parent: -1}, Block{id: 8, parent: 0},
			Block{id: 11, parent: 1}, Block{id: 12, parent: 1}, Block{id: 11, parent: 3},
			Block{id: 12, parent: 1}, Block{id: 11, parent: 5}]
		ir: IRModule{
			types: [IRType{kind: .integer_t, bits: 8}, IRType{kind: .integer_t, bits: 1},
				IRType{kind: .integer_t, bits: 32}, IRType{kind: .integer_t, bits: 64},
				IRType{kind: .integer_t, bits: 128}, IRType{kind: .integer_t, bits: 130},
				IRType{kind: .half_t}, IRType{kind: .bfloat_t}, IRType{kind: .float_t},
				IRType{kind: .double_t}, IRType{kind: .x86_fp80_t}, IRType{kind: .fp128_t},
				IRType{kind: .ppc_fp128_t}, IRType{kind: .array_t, count: 3, refs_count: 1},
				IRType{kind: .vector_t, count: 4, refs_start: 1, refs_count: 1},
				IRType{kind: .struct_t, refs_start: 2, refs_count: 2},
				IRType{kind: .pointer_t, address_space: 1},
				IRType{kind: .function_t, refs_start: 4, refs_count: 2}, IRType{kind: .void_t},
				IRType{kind: .array_t, count: 1000000000000, refs_start: 6, refs_count: 1},
				IRType{kind: .vector_t, count: 2, scalable: true, refs_start: 7, refs_count: 1},
				IRType{kind: .array_t, count: 2, refs_start: 8, refs_count: 1},
				IRType{kind: .label_t}, IRType{kind: .opaque_t, name: 'X'.clone()}]
			references: [0, 2, 2, 2, 2, 2, 2, 8, 2]
			functions: [IRFunction{signature: 17, body_block: 3}, IRFunction{signature: 17, body_block: 5}, IRFunction{signature: 17, declaration: true}]
		}
	}
	f.records.flags |= .noslices; f.values.flags |= .noslices; f.blocks.flags |= .noslices
	for code in [u64(7), 8, 8, 8, 14, 18]! { f.add(1, code, []u64{}) }
	f.add(2, 1, [u64(2)]); f.add(2, 4, [u64(14)]); f.add(2, 4, [u64(3)])
	f.add(2, 1, [u64(15)]); f.add(2, 7, [u64(6), 7])
	f.add(3, 1, [u64(1)]); f.add(4, 1, [u64(3)]); f.add(4, 4, [u64(1)]); f.add(3, 10, []u64{})
	f.add(5, 1, [u64(1)]); f.add(6, 1, [u64(3)]); f.add(6, 4, [u64(19)]); f.add(5, 10, []u64{})
	return f
}
fn constant_reject(f ConstantFixture) {
	if pools := f.ir.constant_pools(f.stream()) { pools.free(); assert false, 'accepted malformed constant fixture' }
}

fn test_constant_scoped_ids_arguments_forward_references_and_no_aliases() {
	mut f := constant_fixture(); defer { f.free() }
	pools := f.ir.constant_pools(f.stream())!
	defer { pools.free() }
	assert pools.declarations.len == 6 && pools.module_values == 9 && pools.constants.len == 5
	assert pools.lookup(0, 0)!.kind == .declaration
	assert pools.lookup(1, 9)!.kind == .argument && pools.lookup(1, 9)!.type_index == 2
	assert pools.lookup(2, 9)!.kind == .argument
	first := pools.lookup(1, 10)!.constant_index
	second := pools.lookup(2, 10)!.constant_index
	assert first != second && pools.scalar_bits(first)! == u64(1) << 63 && pools.scalar_bits(second)! == ~u64(8)
	assert pools.scalar_bits(0)! == 7 && pools.scalar_bits(1)! == 0xffffffff
	assert pools.constants[2].kind == .aggregate
	for scope in [-1, 3, 99] { if _ := pools.lookup(scope, 0) { assert false } }
	if _ := pools.lookup(0, 10) { assert false }
	if _ := pools.lookup(1, ~u64(0)) { assert false }
	if _ := pools.scalar_bits(2) { assert false }
	if _ := pools.scalar_bits(-1) { assert false }
	if _ := pools.scalar_bits(99) { assert false }
	// Module aggregates can forward-reference another module constant.
	f.set(2, 7, 0, 0, 9); f.add(2, 1, [u64(2)]); f.add(2, 4, [u64(6)])
	forward := f.ir.constant_pools(f.stream())!
	assert forward.constants[2].kind == .aggregate && forward.scalar_bits(3)! == 3
	forward.free()
	println('AIR-CONSTANT-IDS: declarations, arguments, scoped reuse, forward references and invalid lookups PASS')
}

fn test_constant_bit_patterns_shapes_and_opaque_failures() {
	mut f := constant_fixture(); defer { f.free() }
	cases := [
		[0, 4], [1, 4], [3, 4], [5, 5], [4, 5], [6, 6], [7, 6], [8, 6], [9, 6],
		[10, 6], [11, 6], [12, 6], [13, 8], [13, 9], [21, 22], [14, 4], [20, 6], [19, 2], [2, 3], [2, 26], [2, 11], [14, 22], [14, 7]
	]
	payloads := [
		[u64(3)], [u64(3)], [u64(1)], [u64(3), 3, 3], [u64(2)],
		[u64(0x7e01)], [u64(0x7fc1)], [u64(0x80000000)], [u64(0x7ff8000000001234)],
		[u64(0x3fff800000000000), 0], [u64(0x0123456789abcdef), 0xfedcba9876543210],
		[u64(0x3ff0000000000000), 0], [u64(65), 0, 255], [u64(65), 66],
		[~u64(0), 0x80000000], [u64(3)], [u64(0x3f800000)], []u64{}, []u64{}, []u64{}, [u64(11), 2, 6], [u64(1), 2, 3, 4], [u64(6), 7, 6, 7]
	]
	expected := [
		[u64(255)], [u64(1)], [u64(1) << 63], [~u64(0), ~u64(0), 3], [u64(1), 0],
		[u64(0x7e01)], [u64(0x7fc1)], [u64(0x80000000)], [u64(0x7ff8000000001234)],
		[u64(0x8000000000000000), 0x3fff], [u64(0x0123456789abcdef), 0xfedcba9876543210],
		[u64(0x3ff0000000000000), 0], [u64(65), 0, 255], [u64(65), 66, 0],
		[u64(0xffffffff), 0x80000000], [u64(0xffffffff)], [u64(0x3f800000)], []u64{}, []u64{}, []u64{}, []u64{}, [u64(1), 2, 3, 4], []u64{}
	]
	for i, item in cases {
		mut b := ConstantBuilder{}
		b.literal(f.ir, Record{code: u64(item[1])}, payloads[i], item[0], 0, 0, 0)!
		pools := IRConstantPools{constants: b.constants, words: b.words}
		assert pools.words == expected[i]
		if i in [15, 16] { assert pools.constants[0].splat }
		if i in [21, 22] { assert !pools.constants[0].splat }
		if i >= 17 { if _ := pools.scalar_bits(0) { assert false } }
		pools.free()
	}
	mut zero := ConstantBuilder{}
	zero.literal(f.ir, Record{code: 2}, []u64{}, 2, 0, 0, 0)!
	pools := IRConstantPools{constants: zero.constants, words: zero.words}
	assert pools.scalar_bits(0)! == 0
	pools.free()
	println('AIR-CONSTANT-BITS: 24 integer/FP/NaN/negative-zero/wide/string/data/splat/zero/opaque cases PASS')
}

fn test_constant_directed_corruptions_and_budgets() {
	modes := ['settype-index', 'settype-void', 'settype-arity', 'literal-arity', 'literal-type', 'wide-count',
		'float-arity', 'empty-aggregate', 'aggregate-count', 'aggregate-id', 'aggregate-argument', 'aggregate-type',
		'string-type', 'string-count', 'string-byte', 'empty-string', 'data-count', 'data-type', 'empty-data',
		'unknown-code', 'empty-opaque', 'blob', 'scope', 'duplicate-pool', 'late-local', 'late-declaration']
	for mode in modes {
		mut f := constant_fixture()
		i := f.find(2, 4, 0)
		match mode {
			'settype-index' { f.set(2, 1, 0, 0, 99) }
			'settype-void' { f.set(2, 1, 0, 0, 18) }
			'settype-arity' { j := f.find(2, 1, 0); f.records[j] = Record{...f.records[j], values_count: 0} }
			'literal-arity' { f.records[i] = Record{...f.records[i], values_count: 0} }
			'literal-type' { f.set(2, 1, 0, 0, 8) }
			'wide-count' { f.records[i] = Record{...f.records[i], code: 5, values_count: 2} }
			'float-arity' { f.set(2, 1, 0, 0, 8); f.records[i] = Record{...f.records[i], code: 6, values_count: 2} }
			'empty-aggregate' { j := f.find(2, 7, 0); f.records[j] = Record{...f.records[j], values_count: 0} }
			'aggregate-count' { j := f.find(2, 7, 0); f.records[j] = Record{...f.records[j], values_count: 1} }
			'aggregate-id' { f.set(2, 7, 0, 0, ~u64(0)) }
			'aggregate-argument' { f.add(4, 1, [u64(15)]); f.add(4, 7, [u64(9), 9]); j := f.find(3, 10, 0); f.records[j] = Record{...f.records[j], code: 1} }
			'aggregate-type' { f.set(2, 7, 0, 0, 0) }
			'string-type' { f.records[i] = Record{...f.records[i], code: 8} }
			'string-count' { f.set(2, 1, 0, 0, 13); f.records[i] = Record{...f.records[i], code: 9} }
			'string-byte' { f.set(2, 1, 0, 0, 13); f.records[i] = Record{...f.records[i], code: 8, values_count: 3}; f.values[f.records[i].values_start] = 256 }
			'empty-string' { f.set(2, 1, 0, 0, 13); f.records[i] = Record{...f.records[i], code: 8, values_count: 0} }
			'data-count' { f.set(2, 1, 0, 0, 21); f.records[i] = Record{...f.records[i], code: 22} }
			'data-type' { f.records[i] = Record{...f.records[i], code: 22} }
			'empty-data' { f.set(2, 1, 0, 0, 21); f.records[i] = Record{...f.records[i], code: 22, values_count: 0} }
			'unknown-code' { f.records[i] = Record{...f.records[i], code: 99} }
			'empty-opaque' { f.records[i] = Record{...f.records[i], code: 11, values_count: 0} }
			'blob' { f.records[i] = Record{...f.records[i], has_blob: true} }
			'scope' { f.blocks[2] = Block{...f.blocks[2], parent: 0} }
			'duplicate-pool' { f.blocks << Block{id: 11, parent: 1} }
			'late-local' { f.add(4, 2, []u64{}) }
			'late-declaration' { f.add(1, 7, []u64{}) }
			else { panic('missing corruption case') }
		}
		constant_reject(f); f.free()
	}
	mut f := constant_fixture(); defer { f.free() }
	mut b := ConstantBuilder{words: []u64{len: max_constant_words}}
	if _ := b.word(0) { assert false }
	unsafe { b.words.free() }
	b = ConstantBuilder{constants: []IRConstant{len: max_constants}}
	if _ := b.literal(f.ir, Record{code: 2}, []u64{}, 2, 0, 0, 0) { assert false }
	unsafe { b.constants.free() }
	b = ConstantBuilder{words: []u64{len: max_constant_words - 1}}
	if _ := b.literal(f.ir, Record{code: 5}, [u64(2)], 4, 0, 0, 0) { assert false }
	unsafe { b.words.free() }
	println('AIR-CONSTANT-REJECT: ${modes.len} directed corruptions and word/count/expansion limits PASS')
}

fn test_constant_operand_mutations_are_bounded() {
	mut f := constant_fixture(); defer { f.free() }
	for i in 0 .. f.values.len {
		for bit in 0 .. 64 {
			f.values[i] ^= u64(1) << u32(bit)
			if pools := f.ir.constant_pools(f.stream()) {
				for constant in pools.constants {
					assert constant.words_start + constant.words_count <= pools.words.len
					value := pools.lookup(constant.scope, constant.number)!
					assert value.kind == .constant && value.constant_index < pools.constants.len
				}
				pools.free()
			}
			f.values[i] ^= u64(1) << u32(bit)
		}
	}
	println('AIR-CONSTANT-MUTATIONS: ${f.values.len * 64} scalar-bit mutations with bounded indexes PASS')
}

fn test_many_constant_scopes_and_implicit_i32() {
	mut f := ConstantFixture{blocks: [Block{id: ~u64(0), parent: -1}, Block{id: 8, parent: 0}]}
	f.blocks.flags |= .noslices; f.records.flags |= .noslices; f.values.flags |= .noslices
	mut functions := []IRFunction{}
	functions.flags |= .noslices
	for _ in 0 .. 512 { f.add(1, 8, []u64{}) }
	for i in 0 .. 512 {
		body := f.blocks.len
		f.blocks << Block{id: 12, parent: 1}; f.blocks << Block{id: 11, parent: body}
		functions << IRFunction{signature: 1, body_block: body}
		f.add(body, 1, [u64(1)]); f.add(body + 1, 4, [u64((i + 1) * 2)]); f.add(body, 10, []u64{})
	}
	f.ir = IRModule{types: [IRType{kind: .integer_t, bits: 32}, IRType{kind: .function_t, refs_count: 2}], references: [0, 0], functions: functions}
	defer { f.free() }
	pools := f.ir.constant_pools(f.stream())!
	defer { pools.free() }
	assert pools.module_values == 512 && pools.constants.len == 512
	for i in 0 .. 512 {
		value := pools.lookup(i + 1, 513)!
		assert pools.scalar_bits(value.constant_index)! == u64(i + 1)
		assert pools.lookup(i + 1, 512)!.kind == .argument
	}
	println('AIR-CONSTANT-SCOPES: 512 isolated scopes, implicit i32 and repeated local IDs PASS')
}
