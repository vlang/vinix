// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module main

// The G13 work-command layouts, checked where a host can check them.
//
// These are the self-checks the AGX probe runs before it will touch an M1, and
// one of them was failing: two blocks of the fragment command were eight bytes
// short of their recovered sizes, which put job_params_2 at 0x3b8 instead of
// 0x3c0 and left every later field in the command adrift of the pointers g13.v
// had already published to firmware. The probe refused to boot, correctly, but
// it took a deploy and a reboot to find out because thirteen checks shared one
// message and no host test ran any of them.
//
// Two things are pinned here. Each validator runs on its own, so a failure
// names itself. And every job-command offset the microsequence is handed is
// checked against the struct field it is supposed to address -- a size
// assertion alone cannot see a field that moved.
//
// gpu.agx.regs holds two more validators. They reach aarch64.kio and memory, so
// a host cannot build them; they are pure arithmetic over constants, with no
// struct layout involved.

import gpu.agx.fw

fn check_layout_validators() {
	assert fw.validate_g13_channel_layouts()
	assert fw.validate_g13_initdata_layouts()
	assert fw.validate_g13_hwdata_layouts()
	assert fw.validate_g13_workqueue_layouts()
	assert fw.validate_g13_event_layouts()
	assert fw.validate_g13_microsequence_layouts()
	assert fw.validate_g13_job_layouts()
	assert fw.validate_g13_compute_layouts()
	assert fw.validate_g13_buffer_layouts()
	assert fw.validate_g13_vertex_layouts()
	assert fw.validate_g13_fragment_layouts()
	// The generated 12.3 column has to describe the same structures the builders
	// in this directory write into, or the 13.5 translation is off a different
	// layout than the one it claims to translate.
	assert fw.validate_g13_initdata_layout_tables()
}

// Firmware dereferences these addresses, so the constant and the field it names
// have to be the same place. This is the check the fragment bug would have hit.
fn check_fragment_offsets() {
	assert __offsetof(fw.G13RunFragment, job_params_1) == fw.g13_fragment_job_params_1_offset
	assert __offsetof(fw.G13RunFragment, job_params_2) == fw.g13_fragment_job_params_2_offset
	assert __offsetof(fw.G13RunFragment, job_params_3) == fw.g13_fragment_job_params_3_offset
	assert __offsetof(fw.G13RunFragment, unk_758_flag) == fw.g13_fragment_unk_758_flag_offset
	assert __offsetof(fw.G13RunFragment, busy_flag) == fw.g13_fragment_busy_flag_offset
	assert __offsetof(fw.G13RunFragment, tvb_overflow_count) == fw.g13_fragment_overflow_count_offset
	assert __offsetof(fw.G13RunFragment, unk_pointee) == fw.g13_fragment_unk_pointee_offset
	assert __offsetof(fw.G13RunFragment, unk_buf_0) == fw.g13_fragment_unk_buf_0_offset
	assert __offsetof(fw.G13RunFragment, cur_ts) == fw.g13_fragment_cur_ts_offset
	assert __offsetof(fw.G13RunFragment, start_ts) == fw.g13_fragment_start_ts_offset
	assert __offsetof(fw.G13RunFragment, end_ts) == fw.g13_fragment_end_ts_offset
}

fn check_vertex_offsets() {
	assert __offsetof(fw.G13RunVertex, job_params_1) == fw.g13_vertex_job_params_1_offset
	assert __offsetof(fw.G13RunVertex, tiling_params) == fw.g13_vertex_tiling_params_offset
	assert __offsetof(fw.G13RunVertex, job_params_2) == fw.g13_vertex_job_params_2_offset
	assert __offsetof(fw.G13RunVertex, unk_pointee) == fw.g13_vertex_unk_pointee_offset
	assert __offsetof(fw.G13RunVertex, unk_buf_0) == fw.g13_vertex_unk_buf_0_offset
	assert __offsetof(fw.G13RunVertex, cur_ts) == fw.g13_vertex_cur_ts_offset
	assert __offsetof(fw.G13RunVertex, start_ts) == fw.g13_vertex_start_ts_offset
	assert __offsetof(fw.G13RunVertex, end_ts) == fw.g13_vertex_end_ts_offset
}

// Translation is identity at 12.3 and a table lookup at 13.5. An offset the
// generator never saw has no answer at all, rather than a 12.3 offset handed to
// 13.5 firmware.
fn check_abi_offset_translation() {
	// Identity at 12.3.
	assert (fw.g13_hwdata_a_offset(.v12_3, 0x004) or { 0 }) == 0x004
	assert (fw.g13_hwdata_a_offset(.v12_3, 0x64c) or { 0 }) == 0x64c
	// HwDataA 0xc is one of the 106 that move.
	assert (fw.g13_hwdata_a_offset(.v13_5_partial, 0x00c) or { 0 }) == 0x010
	// Both Globals writes that reach into the nested GlobalsSub. The second
	// also crosses a field 13.5 inserts inside it, so it moves by more than
	// the containing field does.
	assert (fw.g13_globals_offset(.v13_5_partial, 0x5e) or { 0 }) == 0x6e
	assert (fw.g13_globals_offset(.v13_5_partial, 0x66) or { 0 }) == 0x82

	// An offset the generator never saw has no answer, rather than a 12.3
	// offset handed to 13.5 firmware.
	if _ := fw.g13_hwdata_a_offset(.v13_5_partial, 0x1) {
		assert false, 'an unknown offset must not translate'
	}
	if _ := fw.g13_hwdata_a_offset(.g17_26_5_partial, 0x004) {
		assert false, 'only the two G13 ABIs translate'
	}

	assert (fw.g13_hwdata_a_active_size(.v12_3) or { 0 }) == 0x3d6c
	assert (fw.g13_hwdata_a_active_size(.v13_5_partial) or { 0 }) == 0x421c
	assert (fw.g13_hwdata_b_active_size(.v13_5_partial) or { 0 }) == 0x1884
	assert (fw.g13_globals_active_size(.v13_5_partial) or { 0 }) == 0x12394
	assert (fw.g13_active_io_mapping_count(.v12_3) or { 0 }) == 20
	assert (fw.g13_active_io_mapping_count(.v13_5_partial) or { 0 }) == 25
}

fn check_compute_offsets() {
	assert __offsetof(fw.G13RunCompute, job_params_1) == fw.g13_compute_job_params_1_offset
	assert __offsetof(fw.G13RunCompute, job_params_2) == fw.g13_compute_job_params_2_offset
	assert __offsetof(fw.G13RunCompute, microsequence) == fw.g13_compute_microsequence_offset
	assert __offsetof(fw.G13RunCompute, unk_pointee) == fw.g13_compute_unk_pointee_offset
	assert __offsetof(fw.G13RunCompute, cur_ts) == fw.g13_compute_cur_ts_offset
	assert __offsetof(fw.G13RunCompute, start_ts) == fw.g13_compute_start_ts_offset
	assert __offsetof(fw.G13RunCompute, end_ts) == fw.g13_compute_end_ts_offset
}

fn main() {
	check_layout_validators()
	check_fragment_offsets()
	check_vertex_offsets()
	check_compute_offsets()
	check_abi_offset_translation()
	println('G13 work-command layout tests passed')
}
