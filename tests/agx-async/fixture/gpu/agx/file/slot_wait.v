// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module file

import drm.asahi
import drm.gem
import drm.syncobj
import errno
import event
import gpu.agx.gpu
import proc
import time

enum SlotWake {
	release
	release_before_wait
	firmware_switch
	signal
	masked_signal
	group_stop
	thread_exit
	device_stop
	mapping_failure
	reuse_result_handle
}

__global waiting_file &GpuFile = unsafe { nil }
__global slot_wake SlotWake
__global replacement_result &gem.GemObject = unsafe { nil }

fn wake_waiting_submitter() {
	mut manager := gpu.get_global_manager() or { panic('manager') }
	assert !waiting_file.lock.is_held() && !manager.lock.is_held()
	assert waiting_file.vm.inflight == 0 && manager.prepares == 0 && pending_count == 0
	assert uat_mgr.lease_count == 0 && waiting_file.g13_queues[0].resources.has_file_references()
	assert time.armed() == 1
	mut task := proc.current_thread()
	match slot_wake {
		.release { uat_mgr.make_slot_available() }
		.firmware_switch { uat_mgr.occupied = false }
		.signal { task.pending = 1 }
		.masked_signal {
			task.pending = 1
			task.masked_signals = 1
			uat_mgr.make_slot_available()
		}
		.group_stop { task.process.job_stop_signal = 19 }
		.thread_exit { task.must_exit = true }
		.device_stop { manager.state = .stopped }
		.mapping_failure {
			waiting_file.mapping_retry_blocked = true
			uat_mgr.make_slot_available()
		}
		.reuse_result_handle {
			waiting_file.lock.acquire()
			assert waiting_file.objects.object.references == 2
			gem.unref(waiting_file.objects.object)
			waiting_file.objects = Objects{object: replacement_result}
			waiting_file.queues[0] = LogicalQueue{id: 1, detached: true}
			waiting_file.vm.detached = true
			waiting_file.lock.release()
			uat_mgr.make_slot_available()
		}
		else { panic('generation should have advanced before registration') }
	}
}

fn submit_slot_wait_packet(mut file GpuFile, out &syncobj.SyncObj) int {
	compute := asahi.CmdCompute{cdm_ctrl_stream_base: 0x12340000}
	mut packet := []u8{}
	defer { unsafe { packet.free() } }
	append_packet(mut packet, asahi.cmd_compute, unsafe { &compute }, u16(sizeof(compute)),
		asahi.barrier_none, asahi.barrier_none)
	record := asahi.Sync{handle: out.handle}
	request := asahi.Submit{queue_id: 1, syncs: u64(&record), out_sync_count: 1,
		cmdbuf: u64(packet.data), cmdbuf_size: u32(packet.len)}
	return file.ioctl_modern_submit(&request)
}

fn check_g13_slot_wait() {
	for modern in [false, true]! {
		for reason in [SlotWake.release, .release_before_wait, .firmware_switch, .signal, .masked_signal,
			.group_stop, .thread_exit, .device_stop, .mapping_failure, .reuse_result_handle]! {
			if modern && reason == .reuse_result_handle { continue }
			gpu.reset()
			mut file := new_file()
			mut manager := gpu.get_global_manager() or { panic('manager') }
			mut task := proc.current_thread()
			mut process := proc.Process{}
			task.process = unsafe { &process }
			out := output()
			previous := syncobj.new_fence(99, 1)
			syncobj.replace_fence(out, previous)
			mut before := [128]u8{init: 0xa5}
			mut after := [128]u8{init: 0x5a}
			mut result := gem.GemObject{size: sizeof(before), virt_addr: unsafe { u64(&before[0]) }}
			mut replacement := gem.GemObject{size: sizeof(after), virt_addr: unsafe { u64(&after[0]) }}
			file.objects = Objects{object: &result}
			replacement_result = unsafe { &replacement }
			waiting_file = file
			slot_wake = reason
			uat_mgr.occupied = true
			slot_attempts := uat_mgr.acquire_attempts
			private_before, generations_before := event.wait_counts()
			if reason == .release_before_wait {
				uat_mgr.release_during_bind = true
			} else {
				event.before_wait(wake_waiting_submitter, reason == .firmware_switch)
			}
			code := if modern {
				submit_slot_wait_packet(mut file, out)
			} else {
				submit(mut file, 1, false, unsafe { nil }, out, true)
			}
			assert !file.lock.is_held() && !manager.lock.is_held()
			assert uat_mgr.lease_count == 0 && time.armed() == 0
			expected := match reason {
				.signal, .group_stop, .thread_exit { -int(errno.erestartsys) }
				.device_stop { -19 }
				.mapping_failure { -5 }
				else { 0 }
			}
			assert code == expected
			private_after, generations_after := event.wait_counts()
			assert private_after - private_before == if reason == .firmware_switch { 1 } else { 0 }
			assert generations_after - generations_before == if reason == .release_before_wait { 1 } else { 0 }
			if expected == 0 {
				assert uat_mgr.acquire_attempts == slot_attempts + 2 && manager.prepares == 1
				assert voidptr(fence(out)) != voidptr(previous)
				service_file_work()
				manager.finish_compute(0)
				service_file_work()
				assert syncobj.is_signaled(fence(out))
			} else {
				assert uat_mgr.acquire_attempts == slot_attempts + 1 && manager.prepares == 0
				assert voidptr(fence(out)) == voidptr(previous) && !syncobj.is_signaled(previous)
			}
			if reason == .reuse_result_handle {
				assert result.references == 0 && replacement.references == 1
				assert before[0] != 0xa5 && after[0] == 0x5a
			} else {
				assert result.references == 1
			}
			assert_drained(file)
			waiting_file = unsafe { nil }
			replacement_result = unsafe { nil }
			task.pending = 0
			task.masked_signals = 0
			task.must_exit = false
			task.process = unsafe { nil }
			uat_mgr.occupied = false
		}
	}
	println('G13 slot admission: both ioctl ABIs resumed after release and timer; signal, group stop, device stop, mapping retry and retained result target passed')
}
