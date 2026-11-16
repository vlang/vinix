// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout
import strconv

fn fragment_tail_definitions(fragment string, job string) !g13layout.Definitions {
	mut normalized := ''
	for name in ['BackgroundProgram', 'EotProgram', 'ArrayAddr', 'AuxFBInfo',
		'JobParameters1', 'JobParameters2', 'JobParameters3', 'RunFragment'] {
		normalized += work_tail_record(fragment, name)!
	}
	for name in ['EncoderParams', 'JobMeta', 'TimestampPointers'] {
		normalized += work_tail_record(job, name)!
	}
	return g13layout.parse(normalized)
}

fn fragment_work_aux_value(render string) !u64 {
	initializer := section(render, 'let aux_fb_info =', 'try_init!(fw::fragment::raw::RunFragment', 'Asahi fragment auxiliary default')!
	marker := 'unk3: U64('
	require(initializer.count(marker) == 1, 'Asahi auxiliary default must be one scalar U64 literal')!
	value := initializer.all_after(marker).all_before(')').trim_space()
	return strconv.parse_uint(value, 0, 64)
}

pub fn fragment_work_contract(fragment string, job string, render string) !WorkTailContract {
	defs := fragment_tail_definitions(fragment, job)!
	common := work_tail_contract(defs, 'RunFragment', 'fragment')!
	target := g13layout.Target{ version: 'V13_5' }
	command := defs.lay_out('RunFragment', target)!
	aux := defs.lay_out('AuxFBInfo', target)!
	value := fragment_work_aux_value(render)!
	mut defaults := []WorkFieldDefault{}
	for parent in ['job_params1', 'job_params3'] {
		name := if parent == 'job_params1' { 'JobParameters1' } else { 'JobParameters3' }
		parameters := defs.lay_out(name, target)!
		offset := compute_flag_member(command, parent)! + compute_flag_member(parameters, 'aux_fb_info')! + compute_flag_member(aux, 'unk3')!
		defaults << WorkFieldDefault{ parent + '.aux_fb_info.unk3', int(offset), 8, value }
	}
	return WorkTailContract{ ...common, defaults: defaults }
}

// Selected source-layout model; packed pointer/integer/event representation
// guards run in check_compute_flag_reference before this reference gate.
pub fn fragment_tail_layout_report(fragment string, job string) !string {
	defs := fragment_tail_definitions(fragment, job)!
	mut lines := ['Selected Rust source-layout model (G13; known packed aliases; not a compiled Rust oracle)']
	for version in ['V12_3', 'V13_5'] {
		layout := defs.lay_out('RunFragment', g13layout.Target{ version: version })!
		lines << '${version}: size=0x${layout.size:x}'
		for field in layout.fields {
			lines << '  ${field.name}=0x${field.offset:x} size=0x${field.size:x}'
		}
		parameters := defs.lay_out('JobParameters3', g13layout.Target{ version: version })!
		lines << '  JobParameters3 size=0x${parameters.size:x}'
		for field in parameters.fields { lines << '    ${field.name}=0x${field.offset:x} size=0x${field.size:x}' }
	}
	return lines.join('\n') + '\n'
}

fn check_fragment_tail_local(fragment string) ! {
	getter := section(fragment, 'pub fn g13_fragment_job_params_3_offset_for(',
		'pub fn g13_fragment_unk_758_flag_offset_for(', 'Native third fragment parameter offset')!
	require_order(getter, ['.v12_3 { 0x4b0 }', '.v13_5_partial { 0x4b8 }', 'else { none }'], 'Native versioned third parameter offset')!
	convert := section(fragment, 'pub fn make_g13_fragment_v13_5(',
		'pub fn g13_store_pipeline_binding(', 'Native fragment tail conversion')!
	require_order(convert, ['0x3c8, voidptr(legacy), 0x3c0, 0x0f0)',
		'0x4b8, voidptr(legacy), 0x4b0, 0x220)',
		'0x6f0, voidptr(legacy), 0x6e0, 0x070)',
		'0x768, voidptr(legacy), 0x750, 0x008)',
		'0x770, voidptr(legacy), 0x758, 0x11c)',
		'0x88c, voidptr(legacy), 0x874, 0x03c)',
		'0x8c8, voidptr(legacy), 0x8b0, 0x004)',
		'0x8d0, voidptr(legacy), 0x8b4, 0x030)',
		'0x900, voidptr(legacy), 0x8e4, 0x049)'], 'Native fragment depth/scratch/metadata and complete tail')!
	require(!convert.contains('0x8cc, voidptr(legacy)'), 'Native converter overwrites reserved fragment word')!
	require(!fragment.contains('unk_398_padding'), 'Native third fragment parameter block has extra padding')!
	for name, newer in {'unk_758_flag': '0x770', 'busy_flag': '0x888', 'overflow_count': '0x88c',
		'unk_pointee': '0x8c8', 'unk_buf_0': '0x900', 'cur_ts': '0x918', 'start_ts': '0x920', 'end_ts': '0x928'} {
		body := section(fragment, 'pub fn g13_fragment_' + name + '_offset_for(', '\n}', 'Native fragment pointer ' + name)!
		require_order(body, ['.v12_3 { g13_fragment_' + name + '_offset }', '.v13_5_partial { ' + newer + ' }', 'else { none }'], 'Native fragment pointer ' + name)!
	}
}

fn check_fragment_tail_reference(fragment string, job string, render string, local string) ! {
	defs := fragment_tail_definitions(fragment, job)!
	contract := fragment_work_contract(fragment, job, render)!
	require(contract.fields.len > 100 && contract.defaults.len == 2, 'Unexpected fragment field graph')!
	require(contract.defaults[0].offset == 0xc0 && contract.defaults[1].offset == 0x6e8
		&& contract.defaults[0].value == 0x100000 && contract.defaults[1].value == 0x100000, 'Asahi fragment auxiliary defaults moved')!
	for version in ['V12_3', 'V13_5'] {
		target := g13layout.Target{ version: version }
		layout := defs.lay_out('RunFragment', target)!
		suffix := if version == 'V12_3' { 'v12_3' } else { 'v13_5' }
		require(layout.size == i64(integer_constant(local, 'g13_fragment_' + suffix + '_size', 'Native fragment size')!), 'Asahi/native fragment size mismatch: ' + version)!
		parameters := defs.lay_out('JobParameters3', target)!
		depth := compute_flag_member(layout, 'job_params3')! + compute_flag_member(parameters, 'isp_zls_pixels')!
		require(depth == if version == 'V12_3' { i64(0x750) } else { i64(0x768) }, 'Asahi fragment depth dimensions moved')!
		pointers := defs.lay_out('TimestampPointers', target)!
		require(pointers.size == 16 && compute_flag_member(pointers, 'start_addr')! == 0
			&& compute_flag_member(pointers, 'end_addr')! == 8, 'Asahi timestamp pointer pair changed')!
		if version == 'V12_3' {
			for field, name in {'job_params1': 'job_params_1', 'job_params2': 'job_params_2', 'job_params3': 'job_params_3',
				'unk_758_flag': 'unk_758_flag', 'busy_flag': 'busy_flag', 'tvb_overflow_count': 'overflow_count',
				'unk_pointee': 'unk_pointee', 'unk_buf_0': 'unk_buf_0', 'command_time': 'cur_ts', 'timestamp_pointers': 'start_ts'} {
				require(compute_flag_member(layout, field)! == i64(integer_constant(local, 'g13_fragment_' + name + '_offset', 'Native fragment pointer')!), 'Asahi/native fragment pointer mismatch: ' + name)!
			}
			require(compute_flag_member(layout, 'timestamp_pointers')! + 8 == i64(integer_constant(local, 'g13_fragment_end_ts_offset', 'Native end timestamp')!), 'Asahi/native end timestamp mismatch')!
		} else {
			for name, expected in {'job_params3': i64(0x4b8), 'unk_758_flag': 0x770, 'busy_flag': 0x888,
				'tvb_overflow_count': 0x88c, 'unk_pointee': 0x8c8, 'unk_v13_3': 0x8cc, 'meta': 0x8d0,
				'unk_buf_0': 0x900, 'command_time': 0x918, 'timestamp_pointers': 0x920,
				'user_timestamp_pointers': 0x930, 'client_sequence': 0x940, 'unk_928': 0x944, 'unk_92c': 0x948} {
				require(compute_flag_member(layout, name)! == expected, 'Asahi fragment field moved: ' + name)!
			}
		}
	}
}
