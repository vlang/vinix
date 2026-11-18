// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.asahi
import drm.syncobj
import event
import gpu.agx.gpu
import memory

fn submit_operation_batch(mut file GpuFile, modern bool, input &syncobj.SyncObj, out &syncobj.SyncObj) int {
	if !modern { return submit(mut file, 1, true, input, out, false) }
	compute := asahi.CmdCompute{cdm_ctrl_stream_base: 0x12340000}
	render := asahi.CmdRender{width_px: 64, height_px: 32, layers: 1, samples: 1,
		utile_width_px: 32, utile_height_px: 32}
	mut packet := []u8{}
	defer { unsafe { packet.free() } }
	append_packet(mut packet, asahi.cmd_compute, unsafe { &compute }, u16(sizeof(compute)),
		asahi.barrier_none, asahi.barrier_none)
	append_packet(mut packet, asahi.cmd_render, unsafe { &render }, u16(sizeof(render)),
		asahi.barrier_none, 1)
	with_input := input != unsafe { nil }
	records := [asahi.Sync{handle: if with_input { input.handle } else { u32(0) }},
		asahi.Sync{handle: out.handle}]!
	request := asahi.Submit{queue_id: 1, syncs: unsafe { u64(&records[if with_input { 0 } else { 1 }]) },
		in_sync_count: if with_input { u32(1) } else { u32(0) }, out_sync_count: 1,
		cmdbuf: u64(packet.data), cmdbuf_size: u32(packet.len)}
	return file.ioctl_modern_submit(&request)
}

fn check_operation_retirement(modern bool, with_input bool) {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	manager.ring_full = true
	out := output()
	input := if with_input { output() } else { &syncobj.SyncObj(unsafe { nil }) }
	dependency := syncobj.new_fence(70, 1)
	if with_input { syncobj.replace_fence(input, dependency) }
	assert submit_operation_batch(mut file, modern, input, out) == 0
	early := if with_input { 1 } else { 0 }
	assert manager.active_operations == early && manager.operation_starts == early
	service_file_work()
	assert manager.published.len == 0 && manager.active_operations == early
	if with_input { syncobj.signal(dependency) }
	service_file_work()
	assert manager.published.len == 0 && manager.active_operations == early
	manager.ring_full = false
	service_file_work()
	assert manager.published.len == 2 && manager.operation_starts == 1 && manager.active_operations == 1
	manager.finish_compute(0)
	service_file_work()
	assert manager.active_operations == 1 && manager.operation_ends == 0 && !syncobj.is_signaled(fence(out))
	manager.finish_render(0)
	service_file_work()
	assert manager.operation_ends == 1 && syncobj.is_signaled(fence(out))
	assert_drained(file)
}

fn fail_operation_storage_after_slot_wait() {
	manager := gpu.get_global_manager() or { panic('manager') }
	assert !manager.lock.is_held()
	assert manager.operation_starts == 1 && manager.active_operations == 1
	assert manager.prepares == 0
	memory.fail_next(true)
	uat_mgr.make_slot_available()
}

fn check_operation_refusal(modern bool, wake_failure bool) {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	input := output()
	out := output()
	previous := syncobj.new_fence(71, 1)
	syncobj.replace_fence(input, syncobj.new_fence(72, 1))
	syncobj.replace_fence(out, previous)
	manager.fail_operation_wake = wake_failure
	slot_attempts := uat_mgr.acquire_attempts
	if !wake_failure {
		uat_mgr.occupied = true
		event.before_wait(fail_operation_storage_after_slot_wait, false)
	}
	code := submit_operation_batch(mut file, modern, input, out)
	memory.fail_next(false)
	assert code == if wake_failure { -5 } else { -12 }
	assert manager.operation_starts == if wake_failure { 0 } else { 1 }
	assert manager.operation_starts == manager.operation_ends
	assert uat_mgr.acquire_attempts == slot_attempts + if wake_failure { 0 } else { 2 }
	assert voidptr(fence(out)) == voidptr(previous) && manager.prepares == 0
	assert_drained(file)
}

fn check_submission_operations() {
	for modern in [false, true]! {
		for with_input in [false, true]! { check_operation_retirement(modern, with_input) }
		for wake_failure in [false, true]! { check_operation_refusal(modern, wake_failure) }
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		input := output()
		out := output()
		syncobj.replace_fence(input, syncobj.new_fence(73, 1))
		assert submit_operation_batch(mut file, modern, input, out) == 0
		assert manager.active_operations == 1 && manager.published.len == 0
		manager.stop()
		service_file_work()
		assert manager.active_operations == 0 && manager.operation_ends == 0 && syncobj.is_signaled(fence(out))
		assert_drained(file)
	}
	println('G13 operation ownership: both ABIs count once across dependency wait, mixed-job retirement, wake and storage failure, and shutdown')
}
