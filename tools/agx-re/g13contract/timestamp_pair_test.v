// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import os
import g13layout

fn test_timestamp_native_pair_binding_requires_each_initializer_and_checked_offset() {
	repo := g13layout.repo_root()
	local := os.read_file(repo + '/kernel/gpu/agx/gpu/g13.v')!
	microseq := os.read_file(repo + '/kernel/gpu/agx/fw/microseq.v')!
	check_timestamp_pair_local(local, microseq)!
	for kind in ['vertex', 'fragment', 'compute'] {
		command := if kind == 'compute' { 'command' } else { kind }
		needle := 'user_ts_pointers: job.' + command + '.va + ' + kind + '_user_ts_offset'
		assert local.count(needle) == 2
		first := local.index(needle) or { panic('first binding missing') }
		second := local.index_after(needle, first + needle.len) or { panic('second binding missing') }
		for offset in [first, second] {
			changed := local[..offset] + local[offset..].replace_once(needle, 'user_ts_pointers: 0')
			if _ := check_timestamp_pair_local(changed, microseq) { assert false, kind }
		}
	}
	if _ := check_timestamp_pair_local(local.replace('fw.g13_useq_pipe_vertex) or', 'fw.g13_useq_pipe_fragment) or'), microseq) { assert false }
}

fn test_timestamp_raw_record_selection_refuses_header_and_representation_drift() {
	source := '#[repr(transparent)]\npub(crate) struct OpHeader(u32);\npub(crate) struct Timestamp(OpHeader);\nTimestamp = 0x19,\nTimestamp(OpHeader::with_args(OpCode::Timestamp, (flag as u32) << 31))\n#[repr(C)]\npub(crate) struct Timestamp<\'a> {\n pub(crate) header: op::Timestamp,\n pub(crate) user_ts_pointers: GpuWeakPointer<job::raw::TimestampPointers<\'a>>,\n}\n'
	defs := timestamp_definitions(source)!
	layout := defs.lay_out('Timestamp', g13layout.Target{version: 'V12_3'})!
	assert layout.size == 12 && compute_flag_member(layout, 'user_ts_pointers')! == 4
	for old, changed in {'#[repr(C)]': '#[repr(packed)]', 'OpHeader(u32)': 'OpHeader(u64)', 'header: op::Timestamp': 'header: u64', '<< 31': '<< 30', 'Timestamp = 0x19': 'Timestamp = 0x18', 'GpuWeakPointer<job::raw::TimestampPointers<\'a>>': 'UnknownTimestamp'} {
		if _ := timestamp_definitions(source.replace(old, changed)) {
			// Unknown field types are rejected when laying out the active record.
			changed_defs := timestamp_definitions(source.replace(old, changed))!
			if _ := changed_defs.lay_out('Timestamp', g13layout.Target{version: 'V12_3'}) { assert false, old }
		}
	}
}
