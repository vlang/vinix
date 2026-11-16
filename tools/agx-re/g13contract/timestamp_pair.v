// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

pub struct TimestampWireField {
pub:
	name string
	old_offset int
	new_offset int
	size int
}

pub struct TimestampCommandPair {
pub:
	kind string
	old_time int
	new_time int
	old_kernel int
	new_kernel int
	old_user int
	new_user int
	scratch int
}

pub struct TimestampPairModel {
pub:
	old_size int
	new_size int
	fields []TimestampWireField
	commands []TimestampCommandPair
}

fn timestamp_definitions(source string) !g13layout.Definitions {
	require(source.contains('#[repr(transparent)]\npub(crate) struct OpHeader(u32);')
		&& source.contains('pub(crate) struct Timestamp(OpHeader);'), 'Asahi timestamp opcode representation changed')!
	require(source.contains('Timestamp = 0x19,')
		&& source.contains('Timestamp(OpHeader::with_args(OpCode::Timestamp, (flag as u32) << 31))'), 'Asahi timestamp opcode construction changed')!
	// Select the raw record, not the earlier op::Timestamp tuple wrapper.
	marker := '#[repr(C)]\npub(crate) struct Timestamp<'
	require(source.count(marker) == 1, 'Asahi raw timestamp record must be unique')!
	start := source.index(marker) or { return error('missing raw timestamp') }
	require(source[start..].contains("pub(crate) user_ts_pointers: GpuWeakPointer<job::raw::TimestampPointers<'a>>,"), 'Asahi timestamp user pair target changed')!
	mut normalized := work_tail_record(source[start..], 'Timestamp')!
	require(normalized.count('header: op::Timestamp,') == 1, 'Asahi timestamp header changed')!
	normalized = normalized.replace('header: op::Timestamp,', 'header: u32,')
	return g13layout.parse(normalized)
}

// Selected source-layout model with guarded packed pointer/integer aliases.
// The opcode tuple is modeled as its sole OpHeader field, not Rust-compiled.
pub fn timestamp_pair_model(microseq string, vertex string, fragment string, compute string, job string) !TimestampPairModel {
	defs := timestamp_definitions(microseq)!
	old_target := g13layout.Target{ version: 'V12_3' }
	new_target := g13layout.Target{ version: 'V13_5' }
	old := defs.lay_out('Timestamp', old_target)!
	newer := defs.lay_out('Timestamp', new_target)!
	mut fields := []TimestampWireField{}
	for after in newer.fields {
		mut before_offset := -1
		for before in old.fields {
			if before.name == after.name {
				require(before.size == after.size && before.type_text == after.type_text, 'Timestamp common field changed')!
				before_offset = int(before.offset)
			}
		}
		fields << TimestampWireField{after.name, before_offset, int(after.offset), int(after.size)}
	}
	mut commands := []TimestampCommandPair{}
	for kind, source in {'vertex': vertex, 'fragment': fragment, 'compute': compute} {
		command_defs := if kind == 'fragment' { fragment_tail_definitions(source, job)! }
			else { work_tail_definitions(source, job, kind)! }
		record := if kind == 'vertex' { 'RunVertex' } else if kind == 'fragment' { 'RunFragment' } else { 'RunCompute' }
		before := command_defs.lay_out(record, old_target)!
		after := command_defs.lay_out(record, new_target)!
		for target in [old_target, new_target] {
			pair := command_defs.lay_out('TimestampPointers', target)!
			require(pair.size == 16 && compute_flag_member(pair, 'start_addr')! == 0
				&& compute_flag_member(pair, 'end_addr')! == 8, 'Asahi optional timestamp pair changed')!
		}
		old_user := int(compute_flag_member(before, 'user_timestamp_pointers')!)
		new_user := int(compute_flag_member(after, 'user_timestamp_pointers')!)
		scratch := int(compute_flag_member(after, if kind == 'compute' { 'context_store_req' } else { 'unk_ts' })!)
		require(old_user + 16 <= before.size && new_user + 16 <= after.size && scratch + 8 <= after.size, 'Timestamp pointer exceeds command backing')!
		commands << TimestampCommandPair{kind, int(compute_flag_member(before, 'command_time')!),
			int(compute_flag_member(after, 'command_time')!), int(compute_flag_member(before, 'timestamp_pointers')!),
			int(compute_flag_member(after, 'timestamp_pointers')!), old_user, new_user, scratch}
	}
	return TimestampPairModel{int(old.size), int(newer.size), fields, commands}
}

pub fn timestamp_pair_report(model TimestampPairModel) string {
	mut lines := ['Selected timestamp source-layout model; opcode tuple and packed aliases, not a compiled Rust oracle',
		'Timestamp sizes: 12.3=0x${model.old_size:x}, 13.5=0x${model.new_size:x}']
	for field in model.fields { lines << '${field.name}: old=${field.old_offset}, new=0x${field.new_offset:x}, size=${field.size}' }
	for command in model.commands { lines << '${command.kind}: user pair 0x${command.old_user:x} -> 0x${command.new_user:x}; kernel pair 0x${command.old_kernel:x} -> 0x${command.new_kernel:x}; time 0x${command.old_time:x} -> 0x${command.new_time:x}; 13.5 scratch=0x${command.scratch:x}' }
	return lines.join('\n') + '\n'
}

fn check_timestamp_pair_local(local string, microseq string) ! {
	for kind in ['vertex', 'fragment', 'compute'] {
		require(local.count(kind + '_user_ts_offset := fw.g13_timestamp_user_ts_offset_for(mgr.hw_config.firmware_abi, fw.g13_useq_pipe_' + kind + ') or { return none }') == 1, 'Native timestamp pair getter missing: ' + kind)!
		command := if kind == 'compute' { 'command' } else { kind }
		names := if kind == 'compute' { ['start_timestamp', 'end_timestamp'] } else { [kind + '_ts_start', kind + '_ts_end'] }
		for name in names {
			init := section(local, name + ' := fw.G13MicroseqTimestamp{', '\n\t\t\t}', 'Native timestamp initializer ' + name)!
			require(init.count('user_ts_pointers: job.' + command + '.va + ' + kind + '_user_ts_offset') == 1, 'Native timestamp pair is not bound: ' + name)!
		}
		scratch := if kind == 'vertex' { '0x5e5' } else if kind == 'fragment' { '0x949' } else { '0x2e1' }
		require(local.count('v13_5, &' + names[0] + ', job.' + command + '.va + u64(' + scratch + ')') == 1
			&& local.count('v13_5, &' + names[1] + ', job.' + command + '.va + u64(' + scratch + ')') == 1, 'Native timestamp scratch binding changed')!
	}
	require(microseq.contains('user_ts_pointers u64'), 'Native timestamp pair wire member missing')!
}

fn check_timestamp_pair_reference(model TimestampPairModel, render string, compute string, microseq string) ! {
	require(model.old_size == 0x34 && model.new_size == 0x3c && model.fields.len == 9, 'Asahi timestamp extent changed')!
	mut pair_found := false
	for field in model.fields {
		require(field.name in ['header', 'command_time', 'ts_pointers', 'update_ts', 'work_queue', 'user_ts_pointers', 'unk_ts', 'uuid', 'unk_30_padding'], 'Unknown timestamp field')!
		if field.name == 'user_ts_pointers' {
			require(!pair_found && field.old_offset == 0x24 && field.new_offset == 0x24 && field.size == 8, 'Asahi timestamp pair instruction offset changed')!
			pair_found = true
		}
	}
	require(pair_found, 'Asahi timestamp user pair is missing')!
	for source, count in {render: 4, compute: 2} {
		require(source.count('user_ts_pointers: inner_weak_ptr!(ptr, user_timestamp_pointers),') == count, 'Asahi timestamp pair bindings changed')!
	}
	getter := section(microseq, 'pub fn g13_timestamp_user_ts_offset_for(', 'pub fn g13_microseq_timestamp_v13_5(', 'Native timestamp pair offset')!
	old := section(getter, '.v12_3 {', '.v13_5_partial {', 'Native old timestamp pair offsets')!
	newer := getter.all_after('.v13_5_partial {')
	for command in model.commands {
		require(old.contains('g13_useq_pipe_' + command.kind + ' { u64(0x${command.old_user:x}) }')
			&& newer.contains('g13_useq_pipe_' + command.kind + ' { u64(0x${command.new_user:x}) }'), 'Asahi/native timestamp pair offset differs: ' + command.kind)!
	}
	require(getter.count('else { none }') == 3, 'Native timestamp offsets must reject unknown ABI and pipe')!
}
