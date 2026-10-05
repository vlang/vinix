// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
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

fn object_u32(value voidptr, offset u32) u32 {
	unsafe {
		bytes := &u8(value)
		return u32(bytes[offset]) | (u32(bytes[offset + 1]) << 8)
			| (u32(bytes[offset + 2]) << 16) | (u32(bytes[offset + 3]) << 24)
	}
}

fn object_u64(value voidptr, offset u32) u64 {
	return u64(object_u32(value, offset)) | (u64(object_u32(value, offset + 4)) << 32)
}

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

fn check_channel_offsets() {
	assert __offsetof(fw.FwRunWorkQueueMsg, pipe_type) == 0
	assert __offsetof(fw.FwRunWorkQueueMsg, work_queue_addr) == 0x4
	assert __offsetof(fw.FwRunWorkQueueMsg, write_ptr) == 0xc
	assert __offsetof(fw.FwRunWorkQueueMsg, event_slot) == 0x10
	assert __offsetof(fw.FwRunWorkQueueMsg, is_new) == 0x14
	assert __offsetof(fw.FwRunWorkQueueMsg, timestamp) == 0x18
	assert __offsetof(fw.FwRunWorkQueueMsg, data) == 0x20

	// FWCtl carries the context/slot and a fixed invalidate opcode. The byte
	// range belongs to the handoff slot and must never be encoded at +0x10.
	message := fw.make_g13_fwctl_invalidate(0x1122_3344_5566_7788, 0x40)
	assert sizeof(fw.FwFwCtlMsg) == 0x14
	assert __offsetof(fw.FwFwCtlMsg, addr) == 0
	assert __offsetof(fw.FwFwCtlMsg, slot) == 0xc
	assert __offsetof(fw.FwFwCtlMsg, unk_10) == 0x10
	assert message.addr == 0x1122_3344_5566_7788
	assert message.unk_8 == 0
	assert message.slot == 0x40
	assert message.unk_10 == 1
	assert message.unk_12 == 2
}

fn check_v13_5_command_repacking() {
	assert (fw.g13_compute_active_size(.v13_5_partial) or { 0 }) == 0x320
	assert (fw.g13_vertex_active_size(.v13_5_partial) or { 0 }) == 0x61c
	assert (fw.g13_fragment_active_size(.v13_5_partial) or { 0 }) == 0x974

	mut compute := fw.G13RunCompute{
		tag: 3
		microsequence: 0x1111_2222_3333_4444
		cur_ts: 0x0102_0304_0506_0708
		start_ts: 0x1112_1314_1516_1718
		end_ts: 0x2122_2324_2526_2728
		client_sequence: 0x5a
	}
	compute.job_params_2.preempt_buf_1 = 0x3132_3334_3536_3738
	compute_new := fw.make_g13_compute_v13_5(&compute)
	assert object_u64(voidptr(&compute_new), 0x4) == 0
	assert object_u64(voidptr(&compute_new), 0x1f0) == compute.microsequence
	assert object_u32(voidptr(&compute_new), 0x1fc) == 0
	assert object_u64(voidptr(&compute_new), 0x224) == compute.job_params_2.preempt_buf_1
	assert object_u64(voidptr(&compute_new), 0x2b0) == compute.cur_ts
	assert object_u64(voidptr(&compute_new), 0x2b8) == compute.start_ts
	assert object_u64(voidptr(&compute_new), 0x2c0) == compute.end_ts
	assert object_u32(voidptr(&compute_new), 0x2d8) & 0xff == compute.client_sequence

	mut vertex := fw.G13RunVertex{
		tag: 0
		microsequence: 0x4142_4344_4546_4748
		unk_pointee: 0x5152_5354
		unk_pad: 0x6162_6364
		cur_ts: 0x7172_7374_7576_7778
		start_ts: 0x8182_8384_8586_8788
		end_ts: 0x9192_9394_9596_9798
		client_sequence: 0xa5
	}
	vertex.job_params_2.unk_480[0] = 0xa1a2_a3a4
	vertex_new := fw.make_g13_vertex_v13_5(&vertex)
	assert object_u64(voidptr(&vertex_new), 0x474) == vertex.microsequence
	assert object_u32(voidptr(&vertex_new), 0x488) == vertex.unk_pointee
	assert object_u32(voidptr(&vertex_new), 0x48c) == vertex.unk_pad
	assert object_u32(voidptr(&vertex_new), 0x490) == vertex.job_params_2.unk_480[0]
	assert object_u64(voidptr(&vertex_new), 0x5b4) == vertex.cur_ts
	assert object_u64(voidptr(&vertex_new), 0x5bc) == vertex.start_ts
	assert object_u64(voidptr(&vertex_new), 0x5c4) == vertex.end_ts
	assert object_u32(voidptr(&vertex_new), 0x5dc) & 0xff == vertex.client_sequence

	fragment := fw.G13RunFragment{
		tag: 1
		unk_758_flag: 0xb1b2_b3b4
		busy_flag: 0xc1c2_c3c4
		tvb_overflow_count: 0xd1d2_d3d4
		unk_pointee: 0xe1e2_e3e4
		cur_ts: 0x0101_0202_0303_0404
		start_ts: 0x1111_1212_1313_1414
		end_ts: 0x2121_2222_2323_2424
		client_sequence: 0x6b
	}
	fragment_new := fw.make_g13_fragment_v13_5(&fragment)
	assert object_u32(voidptr(&fragment_new), 0x770) == fragment.unk_758_flag
	assert object_u32(voidptr(&fragment_new), 0x888) == fragment.busy_flag
	assert object_u32(voidptr(&fragment_new), 0x88c) == fragment.tvb_overflow_count
	// Struct7 gains a four-byte prefix; its first legacy word follows it.
	assert object_u32(voidptr(&fragment_new), 0x8c8) == 0
	assert object_u32(voidptr(&fragment_new), 0x8cc) == fragment.unk_pointee
	assert object_u64(voidptr(&fragment_new), 0x918) == fragment.cur_ts
	assert object_u64(voidptr(&fragment_new), 0x920) == fragment.start_ts
	assert object_u64(voidptr(&fragment_new), 0x928) == fragment.end_ts
	assert object_u32(voidptr(&fragment_new), 0x940) & 0xff == fragment.client_sequence
}

fn check_v13_5_queue_objects() {
	assert (fw.g13_workqueue_info_active_size(.v13_5_partial) or { 0 }) == 0xb8
	mut queue := []u8{len: 0xb8}
	priority := fw.g13_workqueue_priority(0) or { panic('missing priority') }
	assert fw.initialize_g13_workqueue_info(queue.data, u64(queue.len), .v13_5_partial,
		0x1000, 0x2000, 0x3000, 0x4000, -1, priority, 0x55aa, 0x8877_6655_4433_2211)
	assert object_u64(queue.data, 0) == 0x1000
	assert object_u32(queue.data, 0xa0) == 0
	assert object_u64(queue.data, 0xa4) == 0x8877_6655_4433_2211
	assert object_u32(queue.data, 0xb4) == 0

	assert (fw.g13_buffer_scene_active_size(.v13_5_partial) or { 0 }) == 0x48
	mut scene := []u8{len: 0x48}
	assert fw.initialize_g13_buffer_scene(scene.data, u64(scene.len), .v13_5_partial,
		0x1234_5678_9abc_def0, 0x0fed_cba9_8765_4321)
	assert object_u64(scene.data, 0x18) == 0x1234_5678_9abc_def0
	assert object_u64(scene.data, 0x24) == 0
	assert object_u64(scene.data, 0x2c) == 0x0fed_cba9_8765_4321
}

fn check_v13_5_microsequences() {
	timestamp := fw.G13MicroseqTimestamp{
		header: 0x8000_0019
		cur_ts: 0x1111_2222_3333_4444
		uuid: 0x5566_7788
		pad_30: 0x99aa_bbcc
	}
	timestamp_new := fw.g13_microseq_timestamp_v13_5(&timestamp,
		0xdead_beef_cafe_babe)
	assert object_u64(voidptr(&timestamp_new), 0x4) == timestamp.cur_ts
	assert object_u64(voidptr(&timestamp_new), 0x2c) == 0xdead_beef_cafe_babe
	assert object_u32(voidptr(&timestamp_new), 0x34) == timestamp.uuid
	assert object_u32(voidptr(&timestamp_new), 0x38) == timestamp.pad_30

	start_vertex := fw.G13MicroseqStartVertex{
		header: 0x22
		unk_178: 0x1122_3344
	}
	start_vertex_new := fw.g13_microseq_start_vertex_v13_5(&start_vertex,
		0x0102_0304_0506_0708, 0x1112_1314_1516_1718)
	assert object_u64(voidptr(&start_vertex_new), 0x178) == 0x0102_0304_0506_0708
	assert object_u64(voidptr(&start_vertex_new), 0x180) == 0x1112_1314_1516_1718
	assert object_u32(voidptr(&start_vertex_new), 0x188) == start_vertex.unk_178

	start_fragment := fw.G13MicroseqStartFragment{
		header: 0x24
		unk_7c: 0xa1a2_a3a4
		uuid: 0xb1b2_b3b4
	}
	start_fragment_new := fw.g13_microseq_start_fragment_v13_5(&start_fragment,
		0x2122_2324_2526_2728, 0x3132_3334_3536_3738)
	assert object_u64(voidptr(&start_fragment_new), 0x7c) == 0
	assert object_u32(voidptr(&start_fragment_new), 0x84) == start_fragment.unk_7c
	assert object_u32(voidptr(&start_fragment_new), 0x90) == start_fragment.uuid
	assert object_u64(voidptr(&start_fragment_new), 0x19c) == 0x2122_2324_2526_2728
	assert object_u64(voidptr(&start_fragment_new), 0x1a4) == 0x3132_3334_3536_3738

	final_fragment := fw.G13MicroseqFinalizeFragment{
		header: 0x25
		unk_6c: 0x4142_4344_4546_4748
		restart_branch_offset: -0x1234
	}
	final_fragment_new := fw.g13_microseq_finalize_fragment_v13_5(&final_fragment)
	assert object_u64(voidptr(&final_fragment_new), 0x6c) == 0
	assert object_u64(voidptr(&final_fragment_new), 0x74) == final_fragment.unk_6c
	assert i32(object_u32(voidptr(&final_fragment_new), 0x9c)) == final_fragment.restart_branch_offset

	start_compute := fw.G13MicroseqStartCompute{
		header: 0x29
	}
	start_compute_new := fw.g13_microseq_start_compute_v13_5(&start_compute,
		0x5152_5354_5556_5758, 0x6162_6364_6566_6768, 0x7172_7374_7576_7778)
	assert object_u64(voidptr(&start_compute_new), 0x154) == 0x5152_5354_5556_5758
	assert object_u64(voidptr(&start_compute_new), 0x15c) == 0x6162_6364_6566_6768
	assert object_u64(voidptr(&start_compute_new), 0x164) == 0x7172_7374_7576_7778

	final_compute := fw.G13MicroseqFinalizeCompute{
		header: 0x2a
		job_params_2: 0x8182_8384_8586_8788
		restart_branch_offset: -0x2345
	}
	final_compute_new := fw.g13_microseq_finalize_compute_v13_5(&final_compute)
	assert object_u64(voidptr(&final_compute_new), 0x18) == final_compute.job_params_2
	assert i32(object_u32(voidptr(&final_compute_new), 0x58)) == final_compute.restart_branch_offset
}

fn main() {
	check_layout_validators()
	check_fragment_offsets()
	check_vertex_offsets()
	check_compute_offsets()
	check_channel_offsets()
	check_abi_offset_translation()
	check_v13_5_command_repacking()
	check_v13_5_queue_objects()
	check_v13_5_microsequences()
	println('G13 work-command layout tests passed')
}
