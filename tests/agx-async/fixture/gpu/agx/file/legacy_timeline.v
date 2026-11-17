// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.asahi
import drm.ioctl
import drm.syncobj
import gpu.agx.gpu
import gpu.agx.submission
import memory

fn submit_legacy_timeline(mut file GpuFile, queue u32, record &ioctl.DrmAsahiSync, input bool) int {
	compute := ioctl.DrmAsahiCmdCompute{}
	command := ioctl.DrmAsahiCommand{
		cmd_type: ioctl.asahi_cmd_compute
		cmd_buffer: unsafe { u64(&compute) }
		cmd_buffer_size: sizeof(compute)
		barriers: [ioctl.asahi_barrier_none, ioctl.asahi_barrier_none]!
	}
	request := ioctl.DrmAsahiSubmit{
		queue_id: queue
		commands: unsafe { u64(&command) }
		command_count: 1
		in_syncs: u64(record)
		out_syncs: u64(record)
		in_sync_count: if input { 1 } else { 0 }
		out_sync_count: if input { 0 } else { 1 }
	}
	return file.ioctl_submit(unsafe { &request })
}

fn check_legacy_timeline() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	target := output()
	mut record := ioctl.DrmAsahiSync{handle: target.handle,
		sync_type: ioctl.asahi_sync_timeline_syncobj, timeline_value: 10}
	before := memory.outstanding_chains()
	// Stage all outputs before reserving any nodes, including with a bad tail.
	mut records := [record, record, record]!
	records[2].extensions = 1
	memory.fail_at(0)
	bad, _ := submission.stage_g13_sync_array(1, unsafe { u64(&records[0]) }, 3, false)
	assert bad == -22 && memory.attempts() == 0
	records[2].extensions = 0
	for failure in 0 .. 3 {
		memory.fail_at(failure)
		code, staged := submission.stage_g13_sync_array(1, unsafe { u64(&records[0]) }, 3, false)
		assert code == -12 && staged.count == 0 && memory.outstanding_chains() == before
	}
	// First fail the output reservation, then fail GPU job storage after it.
	for failure in 1 .. 3 {
		memory.fail_at(failure)
		assert submit_legacy_timeline(mut file, 1, unsafe { &record }, false) == -12
		assert manager.prepares == 0 && memory.outstanding_chains() == before
		if _ := syncobj.get_fence(target) { panic('failed submission published a point') }
		assert_drained(file)
	}
	memory.fail_at(-1)
	assert submit_legacy_timeline(mut file, 1, unsafe { &record }, false) == 0
	first := fence(target)
	assert syncobj.query_timeline_point(target, true) == 10

	compute := asahi.CmdCompute{}
	mut packet := []u8{}
	packet.flags |= .noslices
	defer { unsafe { packet.free() } }
	append_packet(mut packet, asahi.cmd_compute, unsafe { &compute }, u16(sizeof(compute)),
		asahi.barrier_none, asahi.barrier_none)
	mut modern_record := asahi.Sync{handle: target.handle, sync_type: 1, timeline_value: 20}
	mut request := asahi.Submit{queue_id: 2, cmdbuf: u64(packet.data), cmdbuf_size: u32(packet.len),
		syncs: unsafe { u64(&modern_record) }, out_sync_count: 1}
	assert file.ioctl_modern_submit(unsafe { &request }) == 0
	second := fence(target)
	assert second != first && syncobj.query_timeline_point(target, true) == 20
	record.timeline_value = 20
	assert submit_legacy_timeline(mut file, 2, unsafe { &record }, true) == 0
	modern_record.timeline_value = 10
	request.in_sync_count = 1; request.out_sync_count = 0
	assert file.ioctl_modern_submit(unsafe { &request }) == 0
	service_file_work()
	assert manager.published_order.len == 2
	manager.finish_compute_at(1, 0); service_file_work()
	assert manager.published_order.len == 2 && !syncobj.is_signaled(second)
	assert syncobj.query_timeline_point(target, false) == 0
	manager.finish_compute_at(0, 0); service_file_work()
	assert manager.published_order.len == 4 && syncobj.is_signaled(second)
	assert syncobj.query_timeline_point(target, false) == 20
	manager.finish_compute_at(2, 0); manager.finish_compute_at(3, 0); service_file_work()
	assert_drained(file)

	// Legacy zero snapshots the existing head. A retired prefix is available
	// with no pending fence. Repeated/decreasing outputs accept fresh chains.
	for point in [u64(0), 10, 20]! {
		record.timeline_value = point
		code, inputs := submission.stage_g13_sync_array(1, unsafe { u64(&record) }, 1, true)
		assert code == 0 && inputs.item(0).fence == if point == 10 { unsafe { nil } } else { second }
	}
	for point in [u64(20), 19, 0]! {
		record.timeline_value = point
		assert submit_legacy_timeline(mut file, 1, unsafe { &record }, false) == 0
		assert syncobj.query_timeline_point(target, true) == 20
	}
	service_file_work()
	for index in u32(4) .. u32(7) { manager.finish_compute_at(index, 0) }
	service_file_work()
	assert syncobj.is_signaled(fence(target))
	assert_drained(file)
	println('G13 legacy timelines: native and modern producers and consumers share a cumulative prefix. Query, zero, retired points, repeated and decreasing outputs, and reservation rollback passed.')
}
