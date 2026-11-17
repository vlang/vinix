// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.asahi
import drm.syncobj
import gpu.agx.gpu
import gpu.agx.submission
import memory

pub fn measure_chain_reservations() {
	$if macos {
		target := output()
		for count in [u32(1), 65, 129]! {
			records := []asahi.Sync{len: int(count), init: asahi.Sync{handle: target.handle, sync_type: 1}}
			for batch in 0 .. 4 {
				before_blocks, before_bytes := live_record_heap()
				for _ in 0 .. 1000 {
					code, inputs, outputs := submission.stage_packet_syncs(1, u64(records.data), 0, count)
					assert code == 0
					submission.release_sync_array(inputs); submission.release_sync_array(outputs)
					assert memory.outstanding() == 0 && memory.outstanding_chains() == 0
				}
				after_blocks, after_bytes := live_record_heap()
				if batch != 0 {
					assert before_blocks == after_blocks && before_bytes == after_bytes
					println('chain-reservation outputs=${count} batch=${batch} cycles=1000 retained_blocks=${i64(after_blocks) - before_blocks} retained_bytes=${i64(after_bytes) - i64(before_bytes)}')
				}
			}
			unsafe { records.free() }
		}
	} $else { panic('malloc-zone measurement requires macOS') }
}

pub fn run_modern_chain_checks() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	target := output()
	// Every failed buffer/chain reservation must free its unpublished prefix.
	for count in [u32(1), 3, 64, 65, 129]! {
		mut records := []asahi.Sync{len: int(count), init: asahi.Sync{handle: target.handle, sync_type: 1}}
		for index in 0 .. records.len { records[index].timeline_value = u64(index) }
		before := memory.outstanding_chains()
		for failure in 0 .. int(count) + int(count > 64) {
			memory.fail_at(failure)
			code, inputs, outputs := submission.stage_packet_syncs(1, u64(records.data), 0, count)
			assert code == -12 && inputs.count == 0 && outputs.count == 0
			assert memory.outstanding() == 0 && memory.outstanding_chains() == before
			if _ := syncobj.get_fence(target) { panic('failed stage published output') }
		}
		memory.fail_at(-1)
		code, inputs, outputs := submission.stage_packet_syncs(1, u64(records.data), 0, count)
		assert code == 0 && inputs.count == 0 && outputs.count == count
		assert memory.outstanding_chains() == before + int(count)
		submission.release_sync_array(inputs); submission.release_sync_array(outputs)
		assert memory.outstanding() == 0 && memory.outstanding_chains() == before
		unsafe { records.free() }
	}
	invalid := [asahi.Sync{handle: target.handle, sync_type: 1}, asahi.Sync{handle: target.handle, sync_type: 99}]!
	memory.fail_at(0)
	bad, _, _ := submission.stage_packet_syncs(1, unsafe { u64(&invalid[0]) }, 0, 2)
	assert bad == -22 && memory.attempts() == 0, 'all records validated before reserving chains'
	memory.fail_at(-1)
	// Native ioctl outputs are cumulative across queues. A later callback
	// cannot release a root whose earlier payload is unfinished.
	compute := asahi.CmdCompute{}
	mut bytes := []u8{}
	bytes.flags |= .noslices
	defer { unsafe { bytes.free() } }
	append_packet(mut bytes, asahi.cmd_compute, unsafe { &compute }, u16(sizeof(compute)), asahi.barrier_none, asahi.barrier_none)
	mut record := asahi.Sync{handle: target.handle, sync_type: 1, timeline_value: 10}
	mut request := asahi.Submit{queue_id: 1, cmdbuf: u64(bytes.data), cmdbuf_size: u32(bytes.len),
		syncs: unsafe { u64(&record) }, out_sync_count: 1}
	assert file.ioctl_modern_submit(unsafe { &request }) == 0
	first := fence(target)
	request.queue_id = 2; record.timeline_value = 20
	assert file.ioctl_modern_submit(unsafe { &request }) == 0
	second := fence(target)
	assert first != second && !syncobj.is_signaled(first) && !syncobj.is_signaled(second)
	service_file_work()
	assert manager.published_order.len == 2
	manager.finish_compute_at(1, 0); service_file_work()
	assert !syncobj.is_signaled(second) && !syncobj.queue_dependency_ready(second, 1)
	manager.finish_compute_at(0, 0); service_file_work()
	assert syncobj.is_signaled(first) && syncobj.is_signaled(second)
	assert_drained(file)
	// Chain inputs cannot use own-queue leaf elision. A captured root remains
	// stable after replacing the handle and waits for the complete prefix.
	gpu.reset()
	record.timeline_value = 30; request.queue_id = 1
	assert file.ioctl_modern_submit(unsafe { &request }) == 0
	third := fence(target)
	request.in_sync_count = 1; request.out_sync_count = 0
	assert file.ioctl_modern_submit(unsafe { &request }) == 0
	syncobj.replace_fence(target, syncobj.new_fence(999, 1))
	service_file_work()
	assert manager.published_order.len == 1 && !syncobj.is_signaled(third)
	manager.finish_compute_at(0, 0); service_file_work()
	assert manager.published_order.len == 2 && syncobj.is_signaled(third)
	manager.finish_compute_at(1, 0); service_file_work()
	assert_drained(file)
	// Retired lower-prefix lookup can validly return Some(nil).
	syncobj.replace_fence(target, second)
	record.timeline_value = 10
	code, inputs, outputs := submission.stage_packet_syncs(1, unsafe { u64(&record) }, 1, 0)
	assert code == 0 && inputs.count == 1 && inputs.item(0).fence == unsafe { nil }
	submission.release_sync_array(inputs); submission.release_sync_array(outputs)
	// A later packet failure releases its already reserved output node.
	request.in_sync_count = 0; request.out_sync_count = 1; request.cmdbuf_size = 0
	before := memory.outstanding_chains()
	assert file.ioctl_modern_submit(unsafe { &request }) == -22
	assert memory.outstanding_chains() == before
	println('Modern timeline chains: every 1/3/64/65/129-record reservation failure frees its prefix; validation precedes reservation; native two-queue outputs, out-of-order callbacks, captured same-queue chain inputs, retired nil dependencies and post-stage packet rollback pass.')
}
