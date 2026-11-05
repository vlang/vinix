// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Semantic fixtures allow precise ID/schema corruption. Real encoded strings,
// value references and entry graphs are checked with independent LLVM tooling.
struct MetadataFixture {
mut:
	data []u8
	blocks []Block
	records []Record
	values []u64
	types []IRType
	type_refs []int
	functions []IRFunction
	constants []IRConstant
	words []u64
	declarations []int
	scopes []IRConstantScope
	nodes int
	entry int
	input int
	inputs int
	outputs int
	function_value int
}
fn md_fixture_base() MetadataFixture {
	mut f := MetadataFixture{
		blocks: [Block{id: ~u64(0), parent: -1}, Block{id: 8, parent: 0}, Block{id: 15, parent: 1}, Block{id: 12, parent: 1}]
		types: [IRType{kind: .void_t}, IRType{kind: .integer_t, bits: 32}, IRType{kind: .pointer_t, address_space: 1},
			IRType{kind: .function_t, refs_count: 2}, IRType{kind: .pointer_t, refs_start: 2, refs_count: 1}, IRType{kind: .float_t}]
		type_refs: [0, 2, 3]
		functions: [IRFunction{name: 'entry', signature: 3, record: 0, body_block: 3}, IRFunction{name: 'prototype', signature: 3, record: 1, declaration: true}]
		declarations: [0, 1, 2]
		scopes: [IRConstantScope{active: true}]
	}
	f.records.flags |= .noslices; f.values.flags |= .noslices; f.constants.flags |= .noslices; f.words.flags |= .noslices; f.blocks.flags |= .noslices
	f.add(1, 8, []u64{}); f.add(1, 8, []u64{}); f.add(1, 7, []u64{})
	return f
}
fn (mut f MetadataFixture) free() {
	unsafe { f.data.free(); f.blocks.free(); f.records.free(); f.values.free(); f.types.free(); f.type_refs.free(); f.functions.free(); f.constants.free(); f.words.free(); f.declarations.free(); f.scopes.free() }
}
fn (f MetadataFixture) stream() Stream { return Stream{f.blocks, f.records, f.values} }
fn (f MetadataFixture) ir() IRModule { return IRModule{types: f.types, references: f.type_refs, functions: f.functions} }
fn (f MetadataFixture) pools() IRConstantPools { return IRConstantPools{declarations: f.declarations, scopes: f.scopes, constants: f.constants, words: f.words, module_values: u32(3 + f.constants.len)} }
fn (mut f MetadataFixture) add(block int, code u64, values []u64) int {
	index := f.records.len
	f.records << Record{block: block, code: code, values_start: f.values.len, values_count: values.len}
	f.values << values
	return index
}
fn (mut f MetadataFixture) text(text string) int {
	mut values := []u64{cap: text.len}
	defer { unsafe { values.free() } }
	for i in 0 .. text.len { values << u64(text[i]) }
	f.add(2, 1, values)
	index := f.nodes; f.nodes++
	return index
}
fn (mut f MetadataFixture) value(typ int, number u64) int {
	f.add(2, 2, [u64(typ), number])
	index := f.nodes; f.nodes++
	return index
}
fn (mut f MetadataFixture) integer(number u64) int {
	value := f.constants.len
	f.constants << IRConstant{kind: .integer, type_index: 1, bits: 32, words_start: value, words_count: 1}
	f.words << number
	return f.value(1, u64(3 + value))
}
fn (mut f MetadataFixture) tuple(refs []int) int {
	mut values := []u64{cap: refs.len}
	defer { unsafe { values.free() } }
	for ref in refs { values << u64(ref + 1) }
	f.add(2, 3, values)
	index := f.nodes; f.nodes++
	return index
}
fn (mut f MetadataFixture) named(name string, refs []int) {
	mut values := []u64{cap: name.len}
	defer { unsafe { values.free() } }
	for i in 0 .. name.len { values << u64(name[i]) }
	f.add(2, 4, values)
	values.clear()
	for ref in refs { values << u64(ref) }
	f.add(2, 10, values)
}
fn md_fixture() MetadataFixture {
	mut f := md_fixture_base()
	kind := f.text('air.buffer'); location := f.text('air.location_index'); space := f.text('air.address_space')
	arg_name := f.text('air.arg_name'); name := f.text('bufferName'); type_name := f.text('air.arg_type_name'); type_value := f.text('float4')
	size := f.text('air.arg_type_size'); alignment := f.text('air.arg_type_align_size'); read := f.text('air.read'); buffer_size := f.text('air.buffer_size'); unused := f.text('air.arg_unused')
	zero := f.integer(0); one := f.integer(1); sixteen := f.integer(16)
	f.function_value = f.value(4, 0)
	f.input = f.tuple([zero, kind, location, zero, one, space, one, arg_name, name, type_name, type_value, size, sixteen, alignment, sixteen, read, buffer_size, sixteen, unused])
	f.inputs = f.tuple([f.input]); f.outputs = f.tuple([]int{})
	f.entry = f.tuple([f.function_value, f.outputs, f.inputs])
	f.named('air.kernel', [f.entry])
	return f
}
fn (f MetadataFixture) record_for(node int) int {
	mut id := 0
	for i, record in f.records {
		if record.block == 2 && record.code in [u64(1), 2, 3, 5, 7, 13]! {
			if id == node { return i }
			id++
		}
	}
	panic('fixture node missing')
}
fn md_reject(f MetadataFixture) {
	md := f.ir().module_metadata(f.data, f.stream(), f.pools()) or { return }
	defer { md.free() }
	if entries := md.air_entries(f.ir(), f.pools()) { entries.free(); assert false, 'accepted malformed metadata/entry fixture' }
}

fn test_metadata_graph_and_entry_bindings() {
	mut f := md_fixture(); defer { f.free() }
	cycle := f.nodes
	f.tuple([-1, cycle])
	record := f.record_for(cycle)
	f.records[record] = Record{...f.records[record], code: 5}
	f.named('debug.cycle', [cycle])
	md := f.ir().module_metadata(f.data, f.stream(), f.pools())!
	defer { md.free() }
	assert md.nodes[cycle].distinct && md.tuple(cycle)! == [-1, cycle]
	entries := md.air_entries(f.ir(), f.pools())!
	defer { entries.free() }
	assert entries.entries.len == 1 && entries.arguments.len == 1
	entry := entries.entries[0]
	arg := entries.arguments[0]
	assert entry.function == 0 && entry.stage == .kernel && entry.outputs_node == f.outputs
	assert arg.index == 0 && arg.type_index == 2 && arg.kind == 'air.buffer'
	assert arg.has_location && arg.location == 0 && arg.location_count == 1
	assert arg.has_address_space && arg.address_space == 1
	assert arg.has_size && arg.size == 16 && arg.has_alignment && arg.alignment == 16
	assert arg.has_buffer_size && arg.buffer_size == 16 && arg.access == .read && arg.unused
	assert arg.name == 'bufferName' && arg.type_name == 'float4' && arg.condition == -1 && !arg.opaque_attributes
	assert unsafe { arg.name.str == md.nodes[4].text.str }
	println('AIR-METADATA-INDEX: named/nullable IDs, forward cycle, function/stage, types and binding fields PASS')
}

fn test_metadata_string_chunks_and_opaque_slots() {
	mut f := md_fixture_base(); defer { f.free() }
	f.data = [u8(0xc0), 0x40, 0, 0, 97, 98, 99, 88, 89, 90, 95, 1, 0, 0, 0, 122]
	i := f.add(2, 35, [u64(3), 4]); f.records[i] = Record{...f.records[i], has_blob: true, blob: Blob{0, 11}}
	j := f.add(2, 35, [u64(1), 4]); f.records[j] = Record{...f.records[j], has_blob: true, blob: Blob{11, 5}}
	f.add(2, 13, [u64(999)]) // Preserve this debug node's ID without interpreting it.
	f.add(2, 3, [u64(1), 5, 0]) // Empty string, opaque debug slot, null.
	f.named('example', [5])
	md := f.ir().module_metadata(f.data, f.stream(), f.pools())!
	defer { md.free() }
	assert md.nodes.len == 6 && md.text(0)! == '' && md.text(1)! == 'abc' && md.text(2)! == 'XYZ_' && md.text(3)! == 'z'
	assert md.nodes[4].kind == .opaque && md.tuple(5)! == [0, 4, -1]
	f.data[4] = 0
	assert md.text(1)! == 'abc'
	if _ := md.text(-1) { assert false }
	if _ := md.tuple(4) { assert false }
	if _ := md.integer(f.ir(), f.pools(), 0) { assert false }
	println('AIR-METADATA-STRINGS: multiple compressed string chunks, owned bytes, opaque slot IDs and accessor errors PASS')
}

fn test_metadata_and_entry_corruptions() {
	modes := ['unknown-code', 'missing-name', 'duplicate-name', 'name-order', 'name-nul', 'name-byte', 'blob', 'reference', 'named-string', 'missing-value', 'value-type', 'value-arity',
		'entry-arity', 'function-prototype', 'function-global', 'function-type', 'duplicate-entry', 'output-kind', 'kernel-output', 'input-arity', 'input-index', 'input-null',
		'property-missing', 'property-type', 'duplicate-property', 'location-zero', 'location-overflow', 'address-space', 'alignment-zero', 'alignment-three',
		'empty-name', 'orphan-name', 'duplicate-block', 'reserved-code', 'tuple-reference', 'named-reference', 'value-void', 'value-wide',
		'variadic', 'argument-semantic', 'location-missing', 'struct-kind', 'conditional-kind', 'conditional-nested']
	for mode in modes {
		mut f := md_fixture()
		first := f.record_for(0)
		input := f.record_for(f.input)
		entry := f.record_for(f.entry)
		function := f.record_for(f.function_value)
		match mode {
			'unknown-code' { f.records[first] = Record{...f.records[first], code: 99} }
			'missing-name' { f.records[f.records.len - 2] = Record{...f.records[f.records.len - 2], code: 39} }
			'duplicate-name' { f.named('air.kernel', [f.entry]) }
			'name-order' { f.add(2, 4, [u64(97)]); f.add(2, 1, [u64(98)]) }
			'name-nul' { index := f.records.len - 2; f.values[f.records[index].values_start] = 0 }
			'name-byte' { f.values[f.records[first].values_start] = 256 }
			'blob' { f.records[first] = Record{...f.records[first], has_blob: true} }
			'reference' { f.values[f.records[input].values_start] = 999999 }
			'named-string' { last := f.records.last(); f.values[last.values_start] = 0 }
			'missing-value' { f.values[f.records[function].values_start + 1] = ~u64(0) }
			'value-type' { integer := f.record_for(12); f.values[f.records[integer].values_start] = 5 }
			'value-arity' { f.records[function] = Record{...f.records[function], values_count: 1} }
			'entry-arity' { f.records[entry] = Record{...f.records[entry], values_count: 2} }
			'function-prototype' { f.values[f.records[function].values_start + 1] = 1 }
			'function-global' { f.values[f.records[function].values_start + 1] = 2 }
			'function-type' { f.type_refs[2] = 1 }
			'duplicate-entry' { last := f.records.last(); f.values << [u64(f.entry), u64(f.entry)]; f.records[f.records.len - 1] = Record{...last, values_start: f.values.len - 2, values_count: 2} }
			'output-kind' { f.values[f.records[entry].values_start + 1] = 1 }
			'kernel-output' { output := f.record_for(f.outputs); f.records[output] = Record{...f.records[output], values_start: f.records[input].values_start, values_count: 1} }
			'input-arity' { inputs := f.record_for(f.inputs); f.records[inputs] = Record{...f.records[inputs], values_count: 0} }
			'input-index' { f.words[0] = 1 }
			'input-null' { inputs := f.record_for(f.inputs); f.values[f.records[inputs].values_start] = 0 }
			'property-missing' { f.records[input] = Record{...f.records[input], values_count: 3} }
			'property-type' { f.values[f.records[input].values_start + 8] = 13 }
			'duplicate-property' { start := f.values.len; f.values << [u64(13), 1, 10, 10]; f.records[input] = Record{...f.records[input], values_start: start, values_count: 4} }
			'location-zero' { f.words[1] = 0 }
			'location-overflow' { number := f.integer(0xffffffff); f.values[f.records[input].values_start + 3] = u64(number + 1); f.words[1] = 2 }
			'address-space' { f.words[1] = 2 }
			'alignment-zero' { f.words[2] = 0 }
			'alignment-three' { f.words[2] = 3 }
			'empty-name' { name := f.records.len - 2; f.records[name] = Record{...f.records[name], values_count: 0} }
			'orphan-name' { f.add(2, 4, [u64(97)]) }
			'duplicate-block' { f.blocks << Block{id: 15, parent: 1} }
			'reserved-code' { f.records[first] = Record{...f.records[first], code: 42} }
			'tuple-reference' { f.values[f.records[input].values_start] = u64(f.nodes + 1) }
			'named-reference' { last := f.records.last(); f.values[last.values_start] = u64(f.nodes) }
			'value-void' { f.values[f.records[function].values_start] = 0 }
			'value-wide' { f.types[1] = IRType{kind: .integer_t, bits: 128} }
			'variadic' { f.types[3] = IRType{...f.types[3], vararg: true} }
			'argument-semantic' { f.values[f.records[first].values_start] = u64(`x`) }
			'location-missing' { f.records[input] = Record{...f.records[input], values_count: 4} }
			'struct-kind', 'conditional-kind', 'conditional-nested' {
				key := f.text(if mode == 'struct-kind' { 'air.struct_type_info' } else { 'air.function_constant' })
				start := f.values.len
				f.values << if mode == 'struct-kind' { [u64(13), 1, u64(key + 1), 1] }
					else if mode == 'conditional-nested' { [u64(13), u64(key + 1), u64(f.inputs + 1), u64(key + 1)] }
					else { [u64(13), u64(key + 1), 1, 1] }
				f.records[input] = Record{...f.records[input], values_start: start, values_count: 4}
			}
			else { panic('missing metadata corruption') }
		}
		md_reject(f); f.free()
	}
	println('AIR-METADATA-REJECT: ${modes.len} graph/schema/name/type/function/input/property corruptions rejected')
}

fn test_metadata_stages_fragment_linkage_and_no_metadata() {
	for stage in ['air.vertex', 'air.fragment'] {
		mut f := md_fixture(); defer { f.free() }
		// Remove the original root and replace it with a graphics-stage root.
		for i in f.records.len - 2 .. f.records.len { f.records[i] = Record{...f.records[i], code: 39} }
		f.named(stage, [f.entry])
		if stage == 'air.fragment' {
			index := f.integer(0); kind := f.text('air.fragment_input'); linkage := f.text('user(color)'); flat := f.text('air.flat')
			i := f.record_for(f.input); start := f.values.len
			f.values << [u64(index + 1), u64(kind + 1), u64(linkage + 1), u64(flat + 1)]
			f.records[i] = Record{...f.records[i], values_start: start, values_count: 4}
		}
		md := f.ir().module_metadata(f.data, f.stream(), f.pools())!
		entries := md.air_entries(f.ir(), f.pools())!
		assert entries.entries[0].stage == if stage == 'air.vertex' { AIRStage.vertex } else { AIRStage.fragment }
		if stage == 'air.fragment' { assert entries.arguments[0].opaque_attributes && entries.arguments[0].kind == 'air.fragment_input' }
		entries.free(); md.free()
	}
	mut f := md_fixture_base(); defer { f.free() }
	f.blocks[2] = Block{id: 15, parent: 3} // Function metadata does not populate the module index.
	f.add(2, 99, [u64(9999)])
	md := f.ir().module_metadata(f.data, f.stream(), f.pools())!
	entries := md.air_entries(f.ir(), f.pools())!
	assert md.nodes.len == 0 && md.named.len == 0 && entries.entries.len == 0
	entries.free(); md.free()
	println('AIR-METADATA-STAGES: vertex, fragment linkage/interpolation, absent module metadata and local scope isolation PASS')
}

fn test_metadata_resource_limits() {
	mut b := MetadataBuilder{text_bytes: max_metadata_text - 1}
	text := b.copy_text([u64(97)])!
	unsafe { text.free() }
	if value := b.copy_text([u64(98)]) { unsafe { value.free() }; assert false }
	b.edges = []int{len: max_metadata_edges - 1}
	b.references([u64(0)], true)!
	assert b.edges.last() == -1
	if _ := b.references([u64(0)], true) { assert false }
	b.nodes = []IRMetadataNode{len: max_metadata_nodes - 1}
	b.add(IRMetadataNode{})!
	if _ := b.add(IRMetadataNode{}) { assert false }
	b.index().free()
	mut c := MetadataBuilder{}
	defer { c.index().free() }
	if _ := c.references([u64(max_metadata_nodes + 1)], true) { assert false }
	if _ := c.references([u64(max_metadata_nodes)], false) { assert false }
	large := []u64{len: 65537, init: 97}
	defer { unsafe { large.free() } }
	if value := c.copy_text(large) { unsafe { value.free() }; assert false }
	println('AIR-METADATA-LIMITS: exact node/edge/text boundaries and per-string/reference limits PASS')
}

fn test_metadata_operand_mutations() {
	mut base := md_fixture()
	mut count := 0
	for i in 0 .. base.values.len {
		for bit in [0, 1, 15, 31, 63] {
			old := base.values[i]; base.values[i] ^= u64(1) << bit
			if md := base.ir().module_metadata(base.data, base.stream(), base.pools()) {
				if entries := md.air_entries(base.ir(), base.pools()) { entries.free() }
				md.free()
			}
			base.values[i] = old; count++
		}
	}
	base.free()
	println('AIR-METADATA-MUTATIONS: ${count} scalar operand mutations handled with bounded success/error and cleanup')
}

fn test_conditional_arguments_and_unknown_attribute_tails() {
	for conditional in [false, true] {
		mut f := md_fixture()
		i := f.record_for(f.input)
		old := f.records[i]
		original := f.values[old.values_start..old.values_start + old.values_count].clone()
		mut fields := []u64{}
		if conditional {
			key := f.text('air.function_constant')
			global := f.value(2, 2)
			boolean := f.text('bool'); name := f.text('predicate')
			predicate := f.tuple([global, boolean, name])
			fields << [original[0], u64(key + 1), u64(predicate + 1), original[1]]
			fields << original[2..]
		} else {
			key := f.text('air.future_property')
			// A payload that resembles a known key must not be interpreted.
			fields << [original[0], original[1], u64(key + 1), u64(4), u64(7)]
		}
		start := f.values.len; f.values << fields
		f.records[i] = Record{...old, values_start: start, values_count: fields.len}
		md := f.ir().module_metadata(f.data, f.stream(), f.pools())!
		entries := md.air_entries(f.ir(), f.pools())!
		assert entries.arguments[0].opaque_attributes
		if conditional {
			assert entries.arguments[0].condition >= 0 && entries.arguments[0].name == 'bufferName'
		} else { assert entries.arguments[0].name == '' && entries.arguments[0].type_name == '' }
		entries.free(); md.free(); unsafe { original.free(); fields.free() }; f.free()
	}
	println('AIR-METADATA-OPAQUE: conditional predicates retained and unknown property tails never guessed PASS')
}
