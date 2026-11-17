// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.asahi
import gpu.agx.submission
import memory
import usercopy

pub fn (mut f GpuFile) ioctl_modern_submit(data &asahi.Submit) int {
	if data.flags != 0 || data.pad != 0 { return -22 }
	captured := f.capture_submission_queue(data.queue_id) or { return -2 }
	mut transferred := false
	defer { if !transferred { release_submission_queue(captured) } }
	sync_code, inputs, outputs := submission.stage_packet_syncs(f.owner_key, data.syncs, data.in_sync_count, data.out_sync_count)
	if sync_code != 0 { return sync_code }
	defer {
		submission.release_sync_array(inputs)
		submission.release_sync_array(outputs)
	}
	if data.cmdbuf_size == 0 { return -22 }
	if data.cmdbuf == 0 || u64(data.cmdbuf_size - 1) > ~data.cmdbuf { return -14 }
	packet := memory.malloc_packed_fallible(data.cmdbuf_size) @[freed]
	if packet == unsafe { nil } { return -12 }
	defer { memory.free(packet) }
	if !usercopy.copy_from_user(packet, data.cmdbuf, data.cmdbuf_size) { return -14 }
	// Keep both the large parser workspace and decoded command table off the
	// kernel stack. No pointer into this scratch survives submit_g13_staged.
	workspace := memory.malloc_packed_fallible(sizeof(submission.PacketWorkspace)) @[freed]
	if workspace == unsafe { nil } { return -12 }
	defer { memory.free(workspace) }
	storage := memory.malloc_packed_fallible(u64(submission.max_commands) * sizeof(submission.Command)) @[freed]
	if storage == unsafe { nil } { return -12 }
	defer { memory.free(storage) }
	mut commands := []submission.Command{}
	unsafe {
		commands.data = storage
		commands.len = int(submission.max_commands)
		commands.cap = int(submission.max_commands)
		commands.flags = .nogrow | .nofree
	}
	mut parser := unsafe { &submission.PacketWorkspace(workspace) }
	code, count := submission.decode_packet(packet, data.cmdbuf_size, captured.usc_base, false, mut commands, mut parser)
	if code != 0 { return code }
	unsafe { commands.len = int(count) }
	result := f.submit_g13_staged(captured, commands, unsafe { &inputs }, unsafe { &outputs }, 0)
	transferred = result == 0
	return result
}
