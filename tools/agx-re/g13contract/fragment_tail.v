// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn fragment_tail_definitions(fragment string, job string) !g13layout.Definitions {
	mut normalized := ''
	for name in ['BackgroundProgram', 'EotProgram', 'ArrayAddr', 'AuxFBInfo',
		'JobParameters1', 'JobParameters2', 'JobParameters3', 'RunFragment'] {
		normalized += compute_flag_record(fragment, name)!
	}
	for name in ['EncoderParams', 'JobMeta', 'TimestampPointers'] {
		normalized += compute_flag_record(job, name)!
	}
	return g13layout.parse(normalized)
}

// Selected source-layout model; packed pointer/integer/event representation
// guards run in check_compute_flag_reference before this reference gate.
pub fn fragment_tail_layout_report(fragment string, job string) !string {
	defs := fragment_tail_definitions(fragment, job)!
	mut lines := ['Selected Rust source-layout model (G13; known packed aliases; not a compiled Rust oracle)']
	for version in ['V12_3', 'V13_5'] {
		layout := defs.lay_out('RunFragment', g13layout.Target{ version: version })!
		lines << '${version}: size=0x${layout.size:x}'
		for name in ['job_params3', 'unk_pointee', 'meta', 'unk_buf_0'] {
			offset := compute_flag_member(layout, name)!
			lines << '  ${name}=0x${offset:x}'
		}
	}
	return lines.join('\n') + '\n'
}

fn check_fragment_tail_local(fragment string) ! {
	getter := section(fragment, 'pub fn g13_fragment_job_params_3_offset_for(',
		'pub fn g13_fragment_unk_758_flag_offset_for(', 'Native third fragment parameter offset')!
	require_order(getter, ['.v12_3 { 0x4b0 }', '.v13_5_partial { 0x4b8 }', 'else { none }'], 'Native versioned third parameter offset')!
	convert := section(fragment, 'pub fn make_g13_fragment_v13_5(',
		'pub fn g13_store_pipeline_binding(', 'Native fragment tail conversion')!
	require_order(convert, ['0x4b8, voidptr(legacy), 0x4b0, 0x220)',
		'0x8c8, voidptr(legacy), 0x8b8, 0x004)',
		'0x8d0, voidptr(legacy), 0x8bc, 0x030)',
		'0x900, voidptr(legacy), 0x8ec, 0x041)'], 'Native fragment scratch/reserved/metadata separation')!
	require(!convert.contains('0x8cc, voidptr(legacy)'), 'Native converter overwrites reserved fragment word')!
}

fn check_fragment_tail_reference(fragment string, job string, local string) ! {
	defs := fragment_tail_definitions(fragment, job)!
	layout := defs.lay_out('RunFragment', g13layout.Target{ version: 'V13_5' })!
	for name, expected in {'job_params3': i64(0x4b8), 'unk_pointee': 0x8c8,
		'unk_v13_3': 0x8cc, 'meta': 0x8d0, 'unk_buf_0': 0x900} {
		require(compute_flag_member(layout, name)! == expected, 'Asahi fragment field moved: ' + name)!
	}
	require(layout.size <= i64(integer_constant(local, 'g13_fragment_v13_5_size', 'Native fragment backing')!), 'Asahi fragment exceeds native backing')!
}
