// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout
import os

fn test_compute_flag_local_requires_both_calls_and_unaligned_flag_copy() {
	repo := g13layout.repo_root()
	local := os.read_file(repo + '/kernel/gpu/agx/gpu/g13.v')!
	microseq := os.read_file(repo + '/kernel/gpu/agx/fw/microseq.v')!
	compute := os.read_file(repo + '/kernel/gpu/agx/fw/compute.v')!
	check_compute_flag_local(local, microseq, compute)!
	for token in ['v13_5, &finalize, job.command.va + fw.g13_compute_v13_5_flag_offset)',
		'fw.g13_microseq_finalize_compute_v13_5(legacy, flag_address)'] {
		if _ := check_compute_flag_local(local.replace(token, ''), microseq, compute) { assert false, token }
	}
	if _ := check_compute_flag_local(local, microseq.replace('0x6d, flag_address', '0x70, flag_address'), compute) { assert false }
	if _ := check_compute_flag_local(local, microseq, compute.replace('u64(0x305)', 'u64(0x304)')) { assert false }
}

fn test_selected_rust_record_normalization_preserves_versioned_unaligned_pointer_fields() {
	source := "pub(crate) struct Small<'a> {\n" +
		'pub(crate) head: u32,\n#[ver(V >= V13_0B4)]\npub(crate) gap: Array<0xd, u8>,\n' +
		'pub(crate) flag: GpuWeakPointer<U32>, // unaligned\n' +
		'pub(crate) value: EventValue,\n}\n'
	normalized := compute_flag_record(source, 'Small')!
	defs := g13layout.parse(normalized)!
	old := defs.lay_out('Small', g13layout.Target{ version: 'V12_3' })!
	newer := defs.lay_out('Small', g13layout.Target{ version: 'V13_5' })!
	assert compute_flag_member(old, 'flag')! == 4
	assert compute_flag_member(newer, 'flag')! == 0x11
	assert compute_flag_member(newer, 'value')! == 0x1c
	if _ := compute_flag_record(source.replace('pub(crate) head: u32,', 'head ???'), 'Small') { assert false }
	if _ := compute_flag_record(source, 'Missing') { assert false }
	unknown := g13layout.parse(compute_flag_record(source.replace('EventValue', 'UnknownWireType'), 'Small')!)!
	if _ := unknown.lay_out('Small', g13layout.Target{ version: 'V13_5' }) { assert false }
}
