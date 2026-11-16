// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

pub struct WorkFieldSpan {
pub:
	name string
	old_offset int
	new_offset int
	size int
}

pub struct WorkTailContract {
pub:
	kind string
	old_size int
	new_size int
	counter_offset int
	fields []WorkFieldSpan
}

fn work_tail_record(source string, name string) !string {
	start := source.index('pub(crate) struct ' + name) or { return error('missing Rust record ' + name) }
	require(source[..start].trim_space().ends_with('#[repr(C)]'), 'Work record representation changed: ' + name)!
	return compute_flag_record(source, name)
}

fn work_tail_definitions(source string, job string, kind string) !g13layout.Definitions {
	mut normalized := ''
	names := if kind == 'vertex' { ['TilingParameters', 'JobParameters1', 'JobParameters2', 'RunVertex'] }
		else { ['JobParameters1', 'JobParameters2', 'RunCompute'] }
	for name in names { normalized += work_tail_record(source, name)! }
	for name in ['EncoderParams', 'JobMeta', 'TimestampPointers'] { normalized += work_tail_record(job, name)! }
	return g13layout.parse(normalized)
}

// Walk nested records even when their total sizes are unchanged. Compute's
// second parameter block replaces its final word with a prefix at the same
// total extent, so an opaque equal-size parent copy would be wrong.
fn work_tail_fields(defs g13layout.Definitions, name string, path string, old_base int, new_base int) ![]WorkFieldSpan {
	old := defs.lay_out(name, g13layout.Target{ version: 'V12_3' })!
	newer := defs.lay_out(name, g13layout.Target{ version: 'V13_5' })!
	mut spans := []WorkFieldSpan{}
	for before in old.fields {
		for after in newer.fields {
			if before.name != after.name { continue }
			require(before.type_text == after.type_text, 'changed common wire type: ' + path + before.name)!
			label := path + before.name
			if before.type_text in defs.structs {
				spans << work_tail_fields(defs, before.type_text, label + '.', old_base + int(before.offset), new_base + int(after.offset))!
			} else {
				require(before.size == after.size && before.size > 0, 'changed common wire extent: ' + label)!
				spans << WorkFieldSpan{ label, old_base + int(before.offset), new_base + int(after.offset), int(before.size) }
			}
		}
	}
	return spans
}

fn work_tail_contract(defs g13layout.Definitions, record string, kind string) !WorkTailContract {
	old := defs.lay_out(record, g13layout.Target{ version: 'V12_3' })!
	newer := defs.lay_out(record, g13layout.Target{ version: 'V13_5' })!
	return WorkTailContract{ kind, int(old.size), int(newer.size), int(compute_flag_member(newer, 'counter')!),
		work_tail_fields(defs, record, '', 0, 0)! }
}

// This selected source model uses the packed alias representation guards in
// check_compute_flag_reference. It does not execute Rust or firmware.
pub fn work_tail_contracts(vertex string, compute string, job string) ![]WorkTailContract {
	return [work_tail_contract(work_tail_definitions(vertex, job, 'vertex')!, 'RunVertex', 'vertex')!,
		work_tail_contract(work_tail_definitions(compute, job, 'compute')!, 'RunCompute', 'compute')!]
}

pub fn work_tail_layout_report(vertex string, compute string, job string) !string {
	mut lines := ['Selected G13 vertex/compute source-layout model; packed aliases, not a compiled Rust oracle']
	for contract in work_tail_contracts(vertex, compute, job)! {
		lines << '${contract.kind}: 12.3 size=0x${contract.old_size:x}; 13.5 size=0x${contract.new_size:x}; counter=0x${contract.counter_offset:x}'
		for field in contract.fields { lines << '  ${field.name}: 0x${field.old_offset:x} -> 0x${field.new_offset:x}, size=0x${field.size:x}' }
	}
	return lines.join('\n') + '\n'
}

fn check_work_tail_local(vertex string, compute string) ! {
	for kind, source in {'vertex': vertex, 'compute': compute} {
		convert := section(source, 'pub fn make_g13_' + kind + '_v13_5(', 'pub fn validate_g13_', 'Native work conversion ' + kind)!
		require_order(convert, ['0x000, voidptr(legacy), 0x000, 0x004)', 'g13_put_u64(voidptr(&out), 0x004, counter)'], 'Native tag/counter ' + kind)!
		if kind == 'vertex' {
			require(convert.contains('0x00c, voidptr(legacy), 0x004, 0x5d9)'), 'Native vertex must preserve every common field')!
			require(convert.count('g13_copy_bytes(') == 2, 'Unexpected vertex copy span')!
		} else {
			require_order(convert, ['0x00c, voidptr(legacy), 0x004, 0x1f0)',
				'0x200, voidptr(legacy), 0x1f4, 0x05c)', '0x25c, voidptr(legacy), 0x254, 0x085)'], 'Native compute complete common fields')!
			require(convert.count('g13_copy_bytes(') == 4, 'Unexpected compute copy span')!
		}
		require(convert.count('g13_put_u64(') == 1, 'Unexpected work-command added field write')!
	}
}

fn check_work_tail_representations(types string, float_source string) ! {
	require(types.contains('#[repr(C, packed)]\npub(crate) struct Pad<const N: usize>([u8; N]);'), 'Asahi padding representation changed')!
	require(types.contains('#[repr(C)]\npub(crate) struct Array<const N: usize, T>([T; N]);'), 'Asahi array representation changed')!
	require(float_source.contains('#[repr(transparent)]\npub(crate) struct F32(u32);'), 'Asahi software float representation changed')!
}

fn check_work_tail_reference(vertex string, compute string, job string, types string, float_source string, local_vertex string, local_compute string) ! {
	check_work_tail_representations(types, float_source)!
	for contract in work_tail_contracts(vertex, compute, job)! {
		local := if contract.kind == 'vertex' { local_vertex } else { local_compute }
		for suffix, size in {'v12_3': contract.old_size, 'v13_5': contract.new_size} {
			require(int(integer_constant(local, 'g13_' + contract.kind + '_' + suffix + '_size', 'Native work-command extent')!) == size, 'Asahi/native work-command size mismatch: ' + contract.kind + ' ' + suffix)!
		}
		require(contract.counter_offset == 4 && contract.fields.len > 50, 'Unexpected work-command field graph')!
		for field, name in {'unk_pointee': 'unk_pointee', 'job_params1.preempt_buf1': 'job_params_1',
			'command_time': 'cur_ts', 'timestamp_pointers.start_addr': 'start_ts', 'timestamp_pointers.end_addr': 'end_ts'} {
			// The vertex first block begins with unk_0 rather than preempt_buf1.
			selected := if contract.kind == 'vertex' && name == 'job_params_1' { 'job_params1.unk_0' } else { field }
			mut found := false
			for span in contract.fields {
				if span.name != selected { continue }
				found = true
				constant := 'g13_' + contract.kind + '_' + name + '_offset'
				require(int(integer_constant(local, constant, 'Native work pointer')!) == span.old_offset, 'Asahi/native old work pointer mismatch: ' + constant)!
				getter := section(local, 'pub fn ' + constant + '_for(', '\n}', 'Native work pointer getter')!
				require_order(getter, ['.v12_3 { 0x${span.old_offset:x} }', '.v13_5_partial { 0x${span.new_offset:x} }', 'else { none }'], 'Native versioned work pointer ' + name)!
			}
			require(found, 'Missing work pointer field ' + selected)!
		}
	}
}
