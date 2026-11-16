// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn test_microseq_record_header_and_unknown_fields_fail_closed() {
	source := '#[repr(transparent)]\npub(crate) struct OpHeader(u32);\n' + r'pub(crate) struct $name(OpHeader);' + '\nsimple_op!(StartVertex);\n#[repr(C)]\npub(crate) struct StartVertex<\'a> {\n pub(crate) header: op::StartVertex,\n pub(crate) pointer: GpuWeakPointer<U32>,\n #[ver(V >= V13_0B4)]\n pub(crate) counter: U64,\n}\n'
	defs := g13layout.parse(microseq_definition(source, 'StartVertex')!)!
	old := defs.lay_out('StartVertex', g13layout.Target{version: 'V12_3'})!
	newer := defs.lay_out('StartVertex', g13layout.Target{version: 'V13_5'})!
	assert old.size == 12 && newer.size == 20
	for needle in ['#[repr(C)]', 'simple_op!(StartVertex);', '#[repr(transparent)]'] {
		if _ := microseq_definition(source.replace(needle, ''), 'StartVertex') { assert false, needle }
	}
	if _ := microseq_definition(source.replace('header: op::StartVertex', 'header: u64'), 'StartVertex') { assert false }
	changed := microseq_definition(source.replace('counter: U64', 'counter: UnknownWord'), 'StartVertex')!
	changed_defs := g13layout.parse(changed)!
	_ = changed_defs.lay_out('StartVertex', g13layout.Target{version: 'V12_3'})!
	if _ := changed_defs.lay_out('StartVertex', g13layout.Target{version: 'V13_5'}) { assert false }
}

fn test_microseq_common_fields_match_by_identity_across_equal_size_replacement() {
	defs := g13layout.parse('struct Example {\n first: u32,\n #[ver(V < V13_0B4)]\n removed: u32,\n common: U64,\n #[ver(V >= V13_0B4)]\n added: u32,\n}\n')!
	fields := work_tail_fields(defs, 'Example', '', 0, 0)!
	assert fields.len == 2
	assert fields[1].name == 'common' && fields[1].old_offset == 8 && fields[1].new_offset == 4 && fields[1].size == 8
	assert microseq_native_member('event_seq') == 'event_sequence'
	assert microseq_native_member('unk_job_buf') == 'unk_job_buffer'
}

fn test_microseq_attachment_model_derives_members_and_rejects_unsupported_drift() {
	source := 'pub(crate) const MAX_ATTACHMENTS: usize = 16;\n#[repr(C)]\npub(crate) struct Attachment {\n pub(crate) address: U64,\n pub(crate) size: u32,\n pub(crate) unk_c: u16,\n pub(crate) unk_e: u16,\n}\n#[repr(C)]\npub(crate) struct Attachments {\n pub(crate) list: Array<MAX_ATTACHMENTS, Attachment>,\n pub(crate) count: u32,\n}\n'
	layout := microseq_attachment_layout(source)!
	assert layout.size == 16 && layout.list_size == 260 && layout.count_offset == 256
	assert layout.members.len == 4 && layout.members[3].name == 'unk_e' && layout.members[3].offset == 14
	for old, changed in {'= 16;': '= 17;', ' pub(crate) unk_e: u16,\n': '', 'unk_c: u16': 'unk_c: u32',
		'pub(crate) unk_e: u16,': '#[ver(V >= V13_0B4)]\n pub(crate) unk_e: u16,'} {
		if _ := microseq_attachment_layout(source.replace(old, changed)) { assert false, old }
	}
}
