// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout
import os

fn test_work_tail_recurses_when_equal_size_nested_records_move_fields() {
	defs := g13layout.parse('struct Inner {\n#[ver(V >= V13_0B4)]\nprefix: u32,\nvalue: U64,\n#[ver(V < V13_0B4)]\ndiscard: u32,\n}\n' +
		'struct Outer {\ntag: u32,\n#[ver(V >= V13_0B4)]\ncounter: U64,\ninner: Inner,\ntail: u8,\n}\n')!
	contract := work_tail_contract(defs, 'Outer', 'test')!
	assert contract.old_size == 0x14 && contract.new_size == 0x1c
	assert contract.counter_offset == 4
	assert contract.fields.len == 3
	assert contract.fields[1].name == 'inner.value'
	assert contract.fields[1].old_offset == 4 && contract.fields[1].new_offset == 0x10 && contract.fields[1].size == 8
	assert contract.fields[2].old_offset == 0x10 && contract.fields[2].new_offset == 0x18
	unknown := g13layout.parse('struct Outer {\nvalue: UnknownActiveWireType,\n}\n')!
	if _ := work_tail_contract(unknown, 'Outer', 'test') { assert false }
}

fn test_work_tail_local_rejects_truncated_prefix_padding_and_common_flags() {
	repo := g13layout.repo_root()
	vertex := os.read_file(repo + '/kernel/gpu/agx/fw/vertex.v')!
	compute := os.read_file(repo + '/kernel/gpu/agx/fw/compute.v')!
	check_work_tail_local(vertex, compute)!
	if _ := check_work_tail_local(vertex.replace('0x004, 0x5d9)', '0x004, 0x5d1)'), compute) { assert false }
	for token in ['0x004, 0x1f0)', '0x1f4, 0x05c)', '0x254, 0x085)'] {
		assert compute.contains(token)
		if _ := check_work_tail_local(vertex, compute.replace(token, 'wrong-span)')) { assert false, token }
	}
}

fn test_work_tail_requires_record_and_wrapper_representations() {
	record := '#[repr(C)]\npub(crate) struct Small {\npub(crate) value: u32,\n}\n'
	_ = work_tail_record(record, 'Small')!
	if _ := work_tail_record(record.replace('#[repr(C)]', '#[repr(C, packed)]'), 'Small') { assert false }
	types := '#[repr(C, packed)]\npub(crate) struct Pad<const N: usize>([u8; N]);\n' +
		'#[repr(C)]\npub(crate) struct Array<const N: usize, T>([T; N]);'
	float_source := '#[repr(transparent)]\npub(crate) struct F32(u32);'
	check_work_tail_representations(types, float_source)!
	for token in ['#[repr(C, packed)]', '#[repr(C)]'] {
		if _ := check_work_tail_representations(types.replace(token, ''), float_source) { assert false, token }
	}
	if _ := check_work_tail_representations(types, float_source.replace('u32', 'u64')) { assert false }
}
