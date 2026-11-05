// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn layout_fixture() IRModule {
	return IRModule{
		data_layout: 'e-p:64:64-p3:32:32:64:16-i64:64-v96:128:256-a:0:64'.clone()
		types: [IRType{kind: .integer_t, bits: 1}, IRType{kind: .integer_t, bits: 8}, IRType{kind: .integer_t, bits: 24}, IRType{kind: .integer_t, bits: 32}, IRType{kind: .integer_t, bits: 64}, IRType{kind: .float_t},
			IRType{kind: .vector_t, count: 3, refs_count: 1}, IRType{kind: .array_t, count: 2, refs_start: 1, refs_count: 1},
			IRType{kind: .struct_t, refs_start: 2, refs_count: 3}, IRType{kind: .struct_t, packed: true, refs_start: 5, refs_count: 3}, IRType{kind: .pointer_t, address_space: 3},
			IRType{kind: .struct_t, name: 'Node'.clone(), refs_start: 8, refs_count: 2}, IRType{kind: .pointer_t, address_space: 1, refs_start: 10, refs_count: 1},
			IRType{kind: .struct_t, refs_start: 11}, IRType{kind: .array_t, refs_start: 11, refs_count: 1}, IRType{kind: .vector_t, count: 8, refs_start: 12, refs_count: 1},
			IRType{kind: .x86_fp80_t}, IRType{kind: .opaque_t, name: 'Hidden'.clone()}, IRType{kind: .struct_t, name: 'Cycle'.clone(), refs_start: 13, refs_count: 1},
			IRType{kind: .vector_t, count: 4, scalable: true, refs_start: 14, refs_count: 1}, IRType{kind: .array_t, count: 2, refs_start: 15, refs_count: 1}]
		references: [5, 6, 1, 6, 1, 1, 6, 1, 12, 3, 11, 1, 0, 18, 5, 19]
	}
}
fn test_fixed_type_sizes_alignments_and_offsets() {
	ir := layout_fixture(); defer { ir.free() }
	l := ir.type_layouts()!; defer { l.free() }
	assert l.little_endian && l.entries[2].size_bits == 24 && l.entries[2].store_size == 3 && l.entries[2].alloc_size == 4
	vector := l.entries[6]
	assert vector.size_bits == 96 && vector.store_size == 12 && vector.alloc_size == 16 && vector.abi_alignment == 16 && vector.preferred_alignment == 32
	assert l.entries[7].store_size == 32 && l.entries[7].alloc_size == 32
	ordinary := l.entries[8]; packed := l.entries[9]
	assert ordinary.store_size == 48 && ordinary.alloc_size == 48 && ordinary.abi_alignment == 16 && ordinary.preferred_alignment == 16
	assert l.field_offsets[ordinary.fields_start..ordinary.fields_start + ordinary.fields_count] == [u64(0), 16, 32]
	assert packed.store_size == 18 && packed.alloc_size == 18 && packed.abi_alignment == 1 && packed.preferred_alignment == 8
	assert l.field_offsets[packed.fields_start..packed.fields_start + packed.fields_count] == [u64(0), 1, 17]
	assert l.entries[10].size_bits == 32 && l.entries[10].pointer_index_bits == 16 && l.entries[10].preferred_alignment == 8
	assert l.entries[11].alloc_size == 16 && l.entries[12].size_bits == 64
	assert l.entries[13].alloc_size == 0 && l.entries[13].preferred_alignment == 8 && l.entries[14].store_size == 0
	assert l.entries[15].size_bits == 8 && l.entries[15].store_size == 1
	assert l.entries[16].size_bits == 80 && l.entries[16].store_size == 10 && l.entries[16].alloc_size == 16
	assert l.entries[17].status == .unsized && l.entries[18].status == .unsized
	assert l.entries[19].status == .unsupported && l.entries[20].status == .unsupported
	assert ir.types[11].name == 'Node'
	println('AIR-LAYOUT-TYPES: exact bit/store/allocation sizes, vector padding, packed/ordinary fields, pointers/index widths, recursive pointers, zero sizes and unsized/unsupported states PASS')
}
fn test_data_layout_defaults_overrides_and_aggregate_alignment() {
	d := parse_data_layout('')!; defer { d.free() }
	assert d.little_endian && d.pointer_layout(99).bits == 64 && d.pointer_layout(99).address_space == 99
	assert layout_integer(d.integers, 65).abi == 4 && layout_integer(d.integers, 1).abi == 1
	o := parse_data_layout('E-e-p:64:64-p:32:32-i64:64-i64:128-n8:16:32-S128-m:o-A3-P5-G7-Fi64')!; defer { o.free() }
	assert o.little_endian && o.pointer_layout(0).bits == 32 && layout_integer(o.integers, 64).abi == 16
	ir := layout_fixture(); defer { ir.free() }
	view := IRModule{...ir, data_layout: 'E-a:64:128'}
	l := view.type_layouts()!; defer { l.free() }
	assert !l.little_endian && l.entries[13].abi_alignment == 8 && l.entries[13].preferred_alignment == 16
	p := IRTypedProgram{types: ir.types, references: ir.references} // Borrowed semantic test view.
	q := p.type_layouts(view)!; defer { q.free() }
	assert q.entries == l.entries && q.field_offsets == l.field_offsets
	println('AIR-LAYOUT-SPECS: LLVM defaults, last-wins overrides, pointer fallback, big endian, validated hints, aggregate floor and typed-program view PASS')
}
fn test_layout_malformed_specs_and_overflow() {
	modes := ['e-', '-e', 'e--p:64:64', 'ee', 'p:0:8', 'p:64:7', 'p:64:24', 'p:64:64:32', 'p:64:64:64:65', 'p:64:64:64:0',
		'p16777216:64:64', 'p:64', 'i:8', 'i0:8', 'i32:0', 'i8:16', 'f64:64:32', 'v32:32:', 'a:64:32', 'a:0:0', 'a0:8', 'n0', 'n8:', 'ni:1', 'S0', 'm:bad', 'Fz8', 'A16777216', 'x8', 'i999999999999999999999999:8']
	for mode in modes { if d := parse_data_layout(mode) { d.free(); assert false, mode } }
	ir := layout_fixture(); defer { ir.free() }
	mut overflow_types := ir.types.clone(); defer { unsafe { overflow_types.free() } }
	overflow_types[7] = IRType{...overflow_types[7], count: ~u64(0)}
	if l := layout_types(ir.data_layout, overflow_types, ir.references) { l.free(); assert false, 'array size overflow' }
	if _ := layout_round(~u64(0), 8) { assert false, 'padding overflow' }
	if _ := layout_mul(~u64(0), 2) { assert false, 'multiplication overflow' }
	mut types := []IRType{len: 70, init: IRType{kind: .array_t, count: 1, refs_count: 1}}
	mut refs := []int{len: 70}
	defer { unsafe { types.free(); refs.free() } }
	for i in 0 .. 70 { types[i] = IRType{...types[i], refs_start: i}; refs[i] = i + 1 }
	types[69] = IRType{kind: .integer_t, bits: 8}
	if l := layout_types('e', types, refs) { l.free(); assert false, 'type depth budget' }
	println('AIR-LAYOUT-REJECT: ${modes.len} invalid/unsupported specs plus array/padding/multiplication overflow and depth budget rejected')
}
fn test_layout_spec_mutations() {
	ir := layout_fixture(); defer { ir.free() }
	mut bytes := ir.data_layout.bytes(); defer { unsafe { bytes.free() } }
	mut count := 0
	for i in 0 .. bytes.len {
		for bit in [0, 1, 5, 7] {
			old := bytes[i]; bytes[i] ^= u8(1) << bit
			text := bytes.bytestr()
			if d := parse_data_layout(text) { d.free() }
			unsafe { text.free() }; bytes[i] = old; count++
		}
	}
	println('AIR-LAYOUT-MUTATIONS: ${count} layout byte mutations handled with bounded cleanup PASS')
}
