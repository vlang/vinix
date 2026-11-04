// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Deliberate semantic-index fixtures. Real encoded AIR is tested independently
// by air-ir-inspect against LLVM; these permit precise record-level corruption.
struct IRFixture {
mut:
	data []u8
	blocks []Block
	records []Record
	values []u64
}
fn (mut f IRFixture) add(block int, code u64, values []u64) {
	f.records << Record{block: block, code: code, values_start: f.values.len, values_count: values.len}
	f.values << values
}
fn (mut f IRFixture) text(block int, code u64, text string) {
	mut values := []u64{cap: text.len}
	defer { unsafe { values.free() } }
	for i in 0 .. text.len { values << u64(text[i]) }
	f.add(block, code, values)
}
fn (f IRFixture) stream() Stream { return Stream{f.blocks, f.records, f.values} }
fn (mut f IRFixture) free() { unsafe { f.data.free(); f.blocks.free(); f.records.free(); f.values.free() } }
fn (f IRFixture) find(block int, code u64, occurrence int) int {
	mut seen := 0
	for i, record in f.records {
		if record.block == block && record.code == code {
			if seen == occurrence { return i }
			seen++
		}
	}
	panic('fixture record missing')
}
fn (mut f IRFixture) set(block int, code u64, occurrence int, operand int, value u64) {
	record := f.records[f.find(block, code, occurrence)]
	f.values[record.values_start + operand] = value
}
fn ir_fixture() IRFixture {
	mut f := IRFixture{
		data: 'drawread'.bytes()
		blocks: [Block{id: ~u64(0), parent: -1}, Block{id: 8, parent: 0},
			Block{id: 17, parent: 1}, Block{id: 12, parent: 1}, Block{id: 23, parent: 0}]
	}
	f.records.flags |= .noslices; f.values.flags |= .noslices; f.blocks.flags |= .noslices
	f.add(1, 1, [u64(2)])
	f.text(1, 2, 'air64_v29-apple-ios18.0.0')
	f.text(1, 3, 'e-p:64:64')
	f.text(1, 16, 'fixture')
	f.add(2, 1, [u64(12)])
	f.add(2, 2, []u64{}) // 0: void
	f.add(2, 3, []u64{}) // 1: float
	f.add(2, 7, [u64(32)]) // 2: i32
	f.add(2, 8, [u64(5), 1]) // 3: forward reference to identified State
	f.add(2, 12, [u64(4), 1]) // 4: vector
	f.text(2, 19, 'State')
	f.add(2, 20, [u64(0), 3, 4]) // 5: recursive through pointer
	f.add(2, 11, [u64(8), 2]) // 6: array
	f.add(2, 21, [u64(0), 0, 3, 4, 6]) // 7: function
	f.add(2, 8, [u64(7)]) // 8: legacy function pointer
	f.text(2, 19, 'Texture')
	f.add(2, 6, [u64(0)]) // 9: opaque identified struct
	f.add(2, 25, [u64(2)]) // 10: opaque pointer
	f.add(2, 21, [u64(1), 2, 10]) // 11: varargs declaration
	f.add(1, 8, [u64(0), 4, 8, 0, 0, 0, 0, 0, 0, 0])
	f.add(1, 8, [u64(4), 4, 11, 0, 1, 0, 0, 0, 0, 0])
	f.add(3, 1, [u64(3)])
	f.add(3, 10, []u64{}) // Instructions intentionally remain opaque.
	f.records << Record{block: 4, code: 1, has_blob: true, blob: Blob{0, 8}}
	return f
}
fn ir_reject(f IRFixture) {
	if ir := f.stream().ir_module(f.data) { ir.free(); assert false, 'accepted invalid IR fixture' }
}

fn test_ir_types_names_signatures_and_body_mapping() {
	mut f := ir_fixture(); defer { f.free() }
	before := f.data.clone(); defer { unsafe { before.free() } }
	ir := f.stream().ir_module(f.data)!
	defer { ir.free() }
	assert ir.types.len == 12 && ir.functions.len == 2
	assert ir.triple == 'air64_v29-apple-ios18.0.0' && ir.data_layout == 'e-p:64:64' && ir.source_filename == 'fixture'
	assert ir.types[5].name == 'State' && ir.types[9].kind == .opaque_t
	assert ir.types[3].address_space == 1 && ir.references[ir.types[3].refs_start] == 5
	assert ir.functions[0].name == 'draw' && ir.functions[0].signature == 7
	assert ir.functions[0].body_block == 3 && ir.functions[0].basic_blocks == 3 && !ir.functions[0].declaration
	assert ir.functions[1].declaration && ir.functions[1].body_block == -1
	assert unsafe { ir.functions[0].name.str == &f.data[0] }
	for index, expected in {7: 'void (ptr addrspace(1), <4 x float>, [8 x i32])', 11: 'i32 (ptr addrspace(2), ...)', 5: '%"State"', 9: '%"Texture"'} {
		text := ir.type_text(index)!
		assert text == expected
		unsafe { text.free() }
	}
	assert f.data == before
	println('AIR-IR-INDEX: recursive identified types, typed/opaque pointers, signatures, borrowed names and bodies PASS')
}

fn test_ir_directed_corruptions() {
	modes := ['version', 'missing-version', 'duplicate-version', 'type-count', 'large-count', 'missing-count',
		'integer-zero', 'integer-large', 'pointer-ref', 'forward-scalar', 'pointer-void', 'pointer-space',
		'vector-zero', 'vector-struct', 'array-void', 'struct-void', 'struct-packed', 'function-return', 'function-arg',
		'vararg', 'unknown-type', 'name-scope', 'duplicate-type-name', 'missing-type-name', 'opaque-marker',
		'blob-type', 'no-strtab', 'strtab-extent', 'strtab-record', 'strtab-blob',
		'function-offset', 'function-size', 'empty-name', 'nul-name', 'duplicate-name', 'signature-index',
		'signature-kind', 'calling-convention', 'declaration', 'missing-body', 'extra-body', 'body-count',
		'body-first', 'duplicate-block-count', 'module-scope', 'type-scope', 'strtab-scope', 'duplicate-header']
	for mode in modes {
		mut f := ir_fixture()
		match mode {
			'version' { f.set(1, 1, 0, 0, 1) }
			'missing-version' { i := f.find(1, 1, 0); f.records[i] = Record{...f.records[i], code: 99} }
			'duplicate-version' { f.add(1, 1, [u64(2)]) }
			'type-count' { f.set(2, 1, 0, 0, 13) }
			'large-count' { f.set(2, 1, 0, 0, max_ir_types + 1) }
			'missing-count' { i := f.find(2, 1, 0); f.records[i] = Record{...f.records[i], code: 2} }
			'integer-zero' { f.set(2, 7, 0, 0, 0) }
			'integer-large' { f.set(2, 7, 0, 0, (1 << 23) + 1) }
			'pointer-ref' { f.set(2, 8, 0, 0, 12) }
			'forward-scalar' { f.set(2, 8, 0, 0, 4) }
			'pointer-void' { f.set(2, 8, 0, 0, 0) }
			'pointer-space' { f.set(2, 8, 0, 1, 0x1000000) }
			'vector-zero' { f.set(2, 12, 0, 0, 0) }
			'vector-struct' { f.set(2, 12, 0, 1, 5) }
			'array-void' { f.set(2, 11, 0, 1, 0) }
			'struct-void' { f.set(2, 20, 0, 1, 0) }
			'struct-packed' { f.set(2, 20, 0, 0, 2) }
			'function-return' { f.set(2, 21, 0, 1, 7) }
			'function-arg' { f.set(2, 21, 0, 2, 0) }
			'vararg' { f.set(2, 21, 0, 0, 2) }
			'unknown-type' { i := f.find(2, 3, 0); f.records[i] = Record{...f.records[i], code: 26} }
			'name-scope' { i := f.find(2, 20, 0); f.records[i] = Record{...f.records[i], code: 18} }
			'duplicate-type-name' { f.text(2, 19, 'State') }
			'missing-type-name' { i := f.find(2, 19, 0); f.records[i] = Record{...f.records[i], block: 1, code: 99} }
			'opaque-marker' { f.set(2, 6, 0, 0, 1) }
			'blob-type' { i := f.find(2, 3, 0); f.records[i] = Record{...f.records[i], has_blob: true} }
			'no-strtab' { f.blocks[4] = Block{...f.blocks[4], id: 99} }
			'strtab-extent' { i := f.find(4, 1, 0); f.records[i] = Record{...f.records[i], blob: Blob{9, 8}} }
			'strtab-record' { f.add(4, 1, []u64{}) }
			'strtab-blob' { i := f.find(4, 1, 0); f.records[i] = Record{...f.records[i], has_blob: false} }
			'function-offset' { f.set(1, 8, 0, 0, ~u64(0)) }
			'function-size' { f.set(1, 8, 0, 1, ~u64(0)) }
			'empty-name' { f.set(1, 8, 0, 1, 0) }
			'nul-name' { f.data[1] = 0 }
			'duplicate-name' { f.set(1, 8, 1, 0, 0) }
			'signature-index' { f.set(1, 8, 0, 2, 12) }
			'signature-kind' { f.set(1, 8, 0, 2, 2) }
			'calling-convention' { f.set(1, 8, 0, 3, 1024) }
			'declaration' { f.set(1, 8, 0, 4, 2) }
			'missing-body' { f.blocks[3] = Block{...f.blocks[3], id: 99} }
			'extra-body' { f.set(1, 8, 0, 4, 1) }
			'body-count' { f.set(3, 1, 0, 0, 0) }
			'body-first' { i := f.find(3, 1, 0); f.records[i] = Record{...f.records[i], code: 10} }
			'duplicate-block-count' { f.add(3, 1, [u64(3)]) }
			'module-scope' { f.blocks[1] = Block{...f.blocks[1], parent: 2} }
			'type-scope' { f.blocks[2] = Block{...f.blocks[2], parent: 0} }
			'strtab-scope' { f.blocks[4] = Block{...f.blocks[4], parent: 1} }
			'duplicate-header' { f.text(1, 2, 'air64') }
			else { panic('missing corruption mode') }
		}
		ir_reject(f); f.free()
	}
	println('AIR-IR-REJECT: ${modes.len} directed schema/reference/name/scope/body corruptions rejected')
}

fn test_ir_text_and_render_limits() {
	if result := ir_text([u64(256)], 0) { unsafe { result.free() }; assert false }
	if result := ir_text([u64(65)], max_ir_text) { unsafe { result.free() }; assert false }
	mut types := [IRType{kind: .integer_t, bits: 32}]
	mut refs := []int{}
	types.flags |= .noslices; refs.flags |= .noslices
	for i in 0 .. 66 {
		types << IRType{kind: .array_t, count: 1, refs_start: refs.len, refs_count: 1}
		refs << i
	}
	ir := IRModule{types: types, references: refs}
	if result := ir.type_text(66) { unsafe { result.free() }; assert false }
	if result := ir.type_text(-1) { unsafe { result.free() }; assert false }
	ir.free()
	mut f := ir_fixture(); defer { f.free() }
	mut p := IRPrinter{ir: f.stream().ir_module(f.data)!, visits: 65536}
	defer { p.ir.free(); unsafe { p.bytes.free() } }
	if _ := p.typ(0, 0) { assert false }
	p.bytes = []u8{len: 65536}
	if _ := p.write('x') { assert false }
	println('AIR-IR-LIMITS: text budget, render index/depth/work/byte limits PASS')
}

fn test_ir_packed_scalable_escaping_and_operand_mutations() {
	mut f := ir_fixture(); defer { f.free() }
	f.set(2, 20, 0, 0, 1)
	i := f.find(2, 12, 0)
	f.records[i] = Record{...f.records[i], values_start: f.values.len, values_count: 3}
	f.values << [u64(4), 1, 1]
	f.set(2, 19, 1, 0, 92); f.set(2, 19, 1, 6, 34)
	ir := f.stream().ir_module(f.data)!
	assert ir.types[5].packed && ir.types[4].scalable
	text := ir.type_text(4)!
	assert text == '<vscale x 4 x float>'
	escaped := ir.type_text(9)!
	assert escaped == '%"\\5Cextur\\22"'
	unsafe { text.free(); escaped.free() }; ir.free()
	before := f.data.clone(); defer { unsafe { before.free() } }
	for offset in 0 .. f.values.len {
		for bit in 0 .. 64 {
			f.values[offset] ^= u64(1) << u32(bit)
			if model := f.stream().ir_module(f.data) {
				for typ in model.types {
					assert typ.refs_start + typ.refs_count <= model.references.len
				}
				for function in model.functions {
					assert function.signature < model.types.len
					if rendered := model.type_text(function.signature) { unsafe { rendered.free() } }
				}
				model.free()
			}
			assert f.data == before
			f.values[offset] ^= u64(1) << u32(bit)
		}
	}
	println('AIR-IR-MUTATIONS: packed/scalable/escaped names, ${f.values.len * 64} scalar bit mutations with bounded indexes PASS')
}

fn test_ir_empty_module_and_reference_expansion_limit() {
	mut f := IRFixture{blocks: [Block{id: ~u64(0), parent: -1}, Block{id: 8, parent: 0}, Block{id: 17, parent: 1}]}
	defer { f.free() }
	f.records.flags |= .noslices; f.values.flags |= .noslices
	f.add(1, 1, [u64(2)]); f.add(2, 1, [u64(0)])
	empty := f.stream().ir_module(f.data)!
	assert empty.types.len == 0 && empty.functions.len == 0
	empty.free()
	f.set(2, 1, 0, 0, 2)
	f.add(2, 7, [u64(32)])
	values := []u64{len: max_ir_refs + 2}
	f.add(2, 18, values)
	unsafe { values.free() }
	ir_reject(f)
	println('AIR-IR-EXPANSION: empty module and expanded type reference cap PASS')
}
