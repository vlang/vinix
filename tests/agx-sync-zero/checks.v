// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.asahi
import drm.syncobj
import gpu.agx.gpu
import gpu.agx.submission
import memory

pub fn measure_modern_zero_syncs() {
	$if macos {
		input := output()
		dependency := syncobj.new_fence(17, 1)
		syncobj.replace_fence(input, dependency)
		record := asahi.Sync{ handle: input.handle, sync_type: 1 }
		for completed in [false, true]! {
			if completed { syncobj.signal(dependency) }
			for _ in 0 .. 20 {
				code, _, _ := submission.stage_packet_syncs(1, unsafe { u64(&record) }, 1, 0)
				assert code == 0
			}
			for batch in 0 .. 3 {
				before_blocks, before_bytes := live_record_heap()
				for _ in 0 .. 1000 {
					code, inputs, outputs := submission.stage_packet_syncs(1, unsafe { u64(&record) }, 1, 0)
					assert code == 0 && inputs.count == 1 && outputs.count == 0
					assert voidptr(inputs.fences[0]) == voidptr(dependency)
				}
				after_blocks, after_bytes := live_record_heap()
				assert after_blocks == before_blocks && after_bytes == before_bytes
				println('zero-sync completed=${completed} batch=${batch} operations=1000 retained_blocks=${i64(after_blocks) - before_blocks} retained_bytes=${i64(after_bytes) - i64(before_bytes)}')
			}
		}
	} $else {
		panic('malloc-zone retention measurement requires macOS')
	}
}

// Run through both the production sync stager and the packet-to-pending path.
// A zero sequence number must preserve the captured fence, not erase a wait.
pub fn run_modern_zero_checks() {
	mut cases := 0
	for mode in 0 .. 8 {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		mut input := output()
		out := output()
		own_context := file.g13_queues[0].resources.fence_context
		foreign_context := file.g13_queues[1].resources.fence_context
		for iteration in 0 .. 20 {
			dependency := if mode == 3 || mode == 4 {
				syncobj.new_queue_fence(17, u64(iteration), if mode == 3 {
					own_context
				} else {
					foreign_context
				})
			} else {
				syncobj.new_fence(17, u64(iteration))
			}
			if mode == 1 { syncobj.signal(dependency) }
			if mode == 2 { syncobj.signal_error(dependency, -110) }
			syncobj.replace_fence(input, dependency)
			mut records := [asahi.Sync{ handle: input.handle, sync_type: 1 },
				asahi.Sync{ handle: out.handle }]!
			attempts := memory.attempts()
			code, staged, outputs := submission.stage_packet_syncs(file.owner_key,
				unsafe { u64(&records[0]) }, 1, 1)
			assert code == 0 && staged.count == 1 && outputs.count == 1
			assert staged.timeline[0] && staged.timeline_values[0] == 0
			assert memory.attempts() == attempts
			assert !input.lock.is_held() && !dependency.lock.is_held()
			compute := asahi.CmdCompute{}
			mut bytes := []u8{}
			bytes.flags |= .noslices
			append_packet(mut bytes, asahi.cmd_compute, unsafe { &compute },
				u16(sizeof(compute)), asahi.barrier_none, asahi.barrier_none)
			request := asahi.Submit{
				queue_id:       1
				syncs:          unsafe { u64(&records[0]) }
				in_sync_count:  1
				out_sync_count: 1
				cmdbuf:         u64(bytes.data)
				cmdbuf_size:    u32(bytes.len)
			}
			assert file.ioctl_modern_submit(unsafe { &request }) == 0
			unsafe { bytes.free() }
			// Replace/reset/reuse the name after acceptance. Only the old snapshot
			// can release this submission, including when the old fence fails.
			if mode == 5 {
				handle := input.handle
				assert syncobj.destroy(file.owner_key, handle)
				input = output()
				assert input.handle == handle
			}
			if mode == 6 {
				syncobj.replace_fence(input, unsafe { nil })
			} else {
				syncobj.replace_fence(input, syncobj.new_fence(18, 1))
			}
			records[0].handle = ~u32(0)
			published := manager.published.len
			service_file_work()
			if mode != 1 && mode != 2 && mode != 3 {
				assert manager.published.len == published, 'zero-point dependency must block publication'
				assert !syncobj.is_signaled(fence(out))
				// Repeated service cannot discard or recapture the dependency.
				service_file_work()
				assert manager.published.len == published
				if mode == 7 {
					syncobj.signal_error(dependency, -5)
				} else {
					syncobj.signal(dependency)
				}
				service_file_work()
			}
			assert manager.published.len == published + 1
			assert manager.published.last() == 12
			if mode == 3 {
				assert !syncobj.is_signaled(dependency), 'own-queue elision remains valid'
			}
			manager.finish_compute(0)
			service_file_work()
			assert syncobj.is_signaled(fence(out)) && syncobj.get_error(fence(out)) == 0
			assert_drained(file)
			assert voidptr(staged.fences[0]) == voidptr(dependency), 'zero point must preserve the captured fence'
			cases++
		}
	}
	// Zero does not make an empty or missing object a usable input. Output zero
	// still refuses until native cumulative chains are implemented.
	input := output()
	mut record := asahi.Sync{ handle: input.handle, sync_type: 1 }
	code, inputs, outputs := submission.stage_packet_syncs(1, unsafe { u64(&record) }, 1, 0)
	assert code == -22 && inputs.count == 0 && outputs.count == 0
	record.handle = ~u32(0)
	missing, _, _ := submission.stage_packet_syncs(1, unsafe { u64(&record) }, 1, 0)
	assert missing == -2
	record.handle = input.handle
	foreign, _, _ := submission.stage_packet_syncs(2, unsafe { u64(&record) }, 1, 0)
	assert foreign == -2
	zero_output, _, _ := submission.stage_packet_syncs(1, unsafe { u64(&record) }, 0, 1)
	assert zero_output == -95
	assert cases == 160
	println('AGX zero-point inputs: 160 scheduler cases preserve snapshots, block foreign/generic fences, retain own-queue elision, survive reset/replacement/handle reuse, and ignore input errors; empty/missing/foreign handles and output-zero refusal pass')
}
