// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

pub struct MicroseqMember {
pub:
	name string
	native string
	offset int
}

pub struct MicroseqInsertion {
pub:
	name string
	offset int
	size int
}

pub struct MicroseqContract {
pub:
	name string
	kind string
	old_size int
	new_size int
	fields []WorkFieldSpan
	members []MicroseqMember
	insertions []MicroseqInsertion
}

pub struct MicroseqAttachmentLayout {
pub:
	size int
	list_size int
	list_offset int
	count_offset int
	members []MicroseqMember
}

fn microseq_attachment_definitions(source string) !g13layout.Definitions {
	count := integer_constant(source, 'MAX_ATTACHMENTS', 'Asahi attachment capacity')!
	require(count == 16, 'Asahi attachment capacity changed')!
	common := work_tail_record(source, 'Attachment')! + work_tail_record(source, 'Attachments')!
	require(!common.contains('#[ver('), 'Versioned attachment fields require an element-wise array model')!
	return g13layout.parse(common.replace('Array<MAX_ATTACHMENTS, Attachment>', 'Array<${count}, Attachment>'))
}

pub fn microseq_attachment_layout(source string) !MicroseqAttachmentLayout {
	defs := microseq_attachment_definitions(source)!
	target := g13layout.Target{version: 'V12_3'}
	attachment := defs.lay_out('Attachment', target)!
	list := defs.lay_out('Attachments', target)!
	require(attachment.fields.len == 4 && list.fields.len == 2, 'Asahi attachment field graph changed')!
	for field in attachment.fields {
		expected := match field.name { 'address' { 'U64' } 'size' { 'u32' } 'unk_c', 'unk_e' { 'u16' } else { return error('Unknown attachment field') } }
		require(field.type_text == expected, 'Asahi attachment field type changed')!
	}
	mut members := []MicroseqMember{}
	for field in attachment.fields { members << MicroseqMember{field.name, field.name, int(field.offset)} }
	return MicroseqAttachmentLayout{int(attachment.size), int(list.size), int(compute_flag_member(list, 'list')!),
		int(compute_flag_member(list, 'count')!), members}
}

fn microseq_definition(source string, name string) !string {
	require(source.contains('simple_op!(' + name + ');')
		&& source.contains('#[repr(transparent)]\npub(crate) struct OpHeader(u32);')
		&& source.contains(r'pub(crate) struct $name(OpHeader);'), 'Asahi operation header representation changed: ' + name)!
	mut record := work_tail_record(source, name)!
	if name != 'FinalizeCompute' {
		require(record.count('header: op::' + name + ',') == 1, 'Asahi operation header changed: ' + name)!
		record = record.replace('header: op::' + name + ',', 'header: u32,')
	}
	return record
}

fn microseq_native_member(name string) string {
	return match name {
		'job_params1' { 'job_params_1' }
		'job_params2' { 'job_params_2' }
		'event_seq' { 'event_sequence' }
		'unk_job_buf' { 'unk_job_buffer' }
		else { name }
	}
}

// All six G13 start/finalize records, independently of native copy ranges.
// Pointer/integer/array/event guards run before the primary reference gate.
pub fn microseq_field_contracts(source string) ![]MicroseqContract {
	attachments := microseq_attachment_definitions(source)!
	mut contracts := []MicroseqContract{}
	for name, kind in {'StartVertex': 'start_vertex', 'FinalizeVertex': 'finalize_vertex',
		'StartFragment': 'start_fragment', 'FinalizeFragment': 'finalize_fragment',
		'StartCompute': 'start_compute', 'FinalizeCompute': 'finalize_compute'} {
		operation := g13layout.parse(microseq_definition(source, name)!)!
		mut structs := attachments.structs.clone()
		for record, definition in operation.structs { structs[record] = definition }
		defs := g13layout.Definitions{structs: structs, consts: operation.consts}
		old := defs.lay_out(name, g13layout.Target{version: 'V12_3'})!
		newer := defs.lay_out(name, g13layout.Target{version: 'V13_5'})!
		mut members := []MicroseqMember{}
		mut insertions := []MicroseqInsertion{}
		for field in old.fields { members << MicroseqMember{field.name, microseq_native_member(field.name), int(field.offset)} }
		for field in newer.fields {
			mut found := false
			for before in old.fields { if before.name == field.name { found = true } }
			if !found { insertions << MicroseqInsertion{field.name, int(field.offset), int(field.size)} }
		}
		require(old.size <= 0x200 && newer.size <= 0x200, 'Microsequence record exceeds test bound')!
		contracts << MicroseqContract{name, kind, int(old.size), int(newer.size), work_tail_fields(defs, name, '', 0, 0)!, members, insertions}
	}
	return contracts
}

pub fn microseq_field_report(contracts []MicroseqContract) string {
	mut lines := ['Selected G13 start/finalize source-layout model; guarded packed aliases and opcode wrappers, not compiled Rust']
	for contract in contracts {
		lines << '${contract.name}: old=0x${contract.old_size:x}, new=0x${contract.new_size:x}'
		for field in contract.fields { lines << '  ${field.name}: 0x${field.old_offset:x} -> 0x${field.new_offset:x}, size=0x${field.size:x}' }
		for field in contract.insertions { lines << '  added ${field.name}: 0x${field.offset:x}, size=0x${field.size:x}' }
	}
	return lines.join('\n') + '\n'
}

fn check_microseq_field_reference(source string, render string, compute string) ! {
	_ = microseq_attachment_layout(source)!
	for contract in microseq_field_contracts(source)! {
		queue := if contract.name.ends_with('Compute') { compute } else { render }
		builder := section(queue, 'builder.add(microseq::' + contract.name + '::ver {', '})?;', 'Asahi inserted instruction defaults')!
		for field in contract.insertions {
			if field.name in ['counter', 'notifier_buf', 'unk_flag'] {
				require(field.size == 8, 'Asahi inserted scalar width changed')!
				continue
			}
			if field.name in ['unk_7c_0', 'unk_6c_0'] {
				require(builder.contains(field.name + ': U64(0),') && field.size == 8, 'Asahi inserted word default changed')!
			} else {
				require(field.name in ['unk_74', 'unk_9c', 'unk_64', 'unk_79']
					&& builder.contains(field.name + ': Default::default(),'), 'Asahi reserved tail default changed')!
			}
		}
	}
}
