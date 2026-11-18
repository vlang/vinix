// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module file

import drm.asahi
import drm.ioctl
import drm.syncobj
import gpu.agx.gpu
import klock
import memory

__global publication_output &syncobj.SyncObj = unsafe { nil }
__global publication_previous &syncobj.DmaFence = unsafe { nil }
__global publication_finished &syncobj.DmaFence = unsafe { nil }
__global publication_stops bool
__global polling_file &GpuFile = unsafe { nil }

fn stop_during_pending_poll() {
	assert pending_poll_active && pending_head == unsafe { nil }
	mut file := unsafe { polling_file }
	assert submit(mut file, 2, false, unsafe { nil }, unsafe { nil }, false) == 0
	mut manager := gpu.get_global_manager() or { panic('manager') }
	manager.stop()
	service_file_work()
	assert pending_poll_requested && pending_count == 1
}

fn check_pending_poll_handoff() {
	gpu.reset()
	mut file := new_file()
	assert submit(mut file, 1, false, unsafe { nil }, unsafe { nil }, false) == 0
	polling_file = file
	klock.after_release_once(unsafe { &pending_lock }, stop_during_pending_poll)
	service_file_work()
	assert !pending_poll_active && !pending_poll_requested
	assert_drained(file)
	polling_file = unsafe { nil }
	println('G13 pending poll: work appended after the snapshot retires after the final worker poll overlaps')
}

fn retire_before_output_installation() {
	assert pending_count == 1
	assert voidptr(fence(publication_output)) == voidptr(publication_previous)
	publication_finished = unsafe { pending_head.final_fence }
	assert publication_finished != unsafe { nil } && publication_finished.seqno == 1
	if publication_stops {
		mut manager := gpu.get_global_manager() or { panic('manager') }
		manager.stop()
	}
	process_pending_submissions()
	assert pending_count == 0 && syncobj.is_signaled(publication_finished)
	assert voidptr(fence(publication_output)) == voidptr(publication_previous)
}

fn watch_registration(data voidptr) {
	completion := unsafe { &G13SubmitCompletion(data) }
	assert completion.submission.final_fence == unsafe { nil }
	manager := gpu.get_global_manager() or { panic('manager') }
	klock.after_release_once(unsafe { &manager.lock }, retire_before_output_installation)
}

fn submit_with_output(mut file GpuFile, modern bool, target &syncobj.SyncObj, timeline bool) int {
	sync_type := if timeline { ioctl.asahi_sync_timeline_syncobj } else { ioctl.asahi_sync_syncobj }
	point := if timeline { u64(50) } else { u64(0) }
	if !modern {
		record := ioctl.DrmAsahiSync{handle: target.handle, sync_type: sync_type, timeline_value: point}
		return submit_legacy_timeline(mut file, 1, unsafe { &record }, false)
	}
	compute := asahi.CmdCompute{}
	mut packet := []u8{cap: int(sizeof(asahi.CmdHeader) + sizeof(compute))}
	defer { unsafe { packet.free() } }
	append_packet(mut packet, asahi.cmd_compute, unsafe { &compute }, u16(sizeof(compute)),
		asahi.barrier_none, asahi.barrier_none)
	record := asahi.Sync{handle: target.handle, sync_type: sync_type, timeline_value: point}
	request := asahi.Submit{queue_id: 1, syncs: unsafe { u64(&record) }, out_sync_count: 1,
		cmdbuf: u64(packet.data), cmdbuf_size: u32(packet.len)}
	return file.ioctl_modern_submit(unsafe { &request })
}

fn check_output_publication() {
	for modern in [false, true]! {
		for timeline in [false, true]! {
			for mode in 0 .. 3 {
				gpu.reset()
				mut file := new_file()
				mut manager := gpu.get_global_manager() or { panic('manager') }
				out := output()
				previous := syncobj.new_fence(91, 1)
				syncobj.signal(previous)
				syncobj.replace_fence(out, previous)
				chains := memory.outstanding_chains()
				if mode == 0 {
					// The last callback installs successfully, then registration
					// sees shutdown before the queue acquires ownership.
					manager.stop_callback_at = 0
					assert submit_with_output(mut file, modern, out, timeline) == -19
					assert voidptr(fence(out)) == voidptr(previous)
					assert file.g13_queues[0].resources.fence_seqno == 0
					assert memory.outstanding_chains() == chains
				} else {
					publication_output = out
					publication_previous = previous
					publication_stops = mode == 2
					manager.immediate_complete = true
					manager.inspect_callback_at = 0
					manager.on_callback = watch_registration
					assert submit_with_output(mut file, modern, out, timeline) == 0
					assert publication_finished != unsafe { nil }
					head := fence(out)
					assert syncobj.is_signaled(head)
					assert voidptr(syncobj.chain_contained(head)) == voidptr(publication_finished)
					assert syncobj.get_error(publication_finished) == if mode == 2 { -19 } else { 0 }
					assert file.g13_queues[0].resources.fence_seqno == 1
					assert memory.outstanding_chains() == chains + if timeline { 1 } else { 0 }
					publication_output = unsafe { nil }
					publication_previous = unsafe { nil }
					publication_finished = unsafe { nil }
				}
				assert_drained(file)
			}
		}
	}
	println('G13 output publication: 12 real ioctl cases preserve outputs on rejection and publish completed or stopped fences after the worker frees the node')
}
