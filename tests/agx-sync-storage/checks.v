// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.asahi
import drm.syncobj
import gpu.agx.gpu
import gpu.agx.submission
import memory
import usercopy

fn sync_records(inputs u32, outputs u32, input u32, gate u32, first u32, last u32) []asahi.Sync {
	mut records := []asahi.Sync{len: int(inputs + outputs)}
	for index := u32(0); index < inputs; index++ {
		records[index] = asahi.Sync{
			handle:    if index + 1 == inputs { gate } else { input }
			sync_type: if index + 1 == inputs { u32(1) } else { 0 }
		}
	}
	for index := u32(0); index < outputs; index++ {
		records[inputs + index] = asahi.Sync{
			handle: if index + 1 == outputs {
				last
			} else {
				first
			}
		}
	}
	return records
}

pub fn measure_large_syncs() {
	$if macos {
		input := output()
		target := output()
		syncobj.replace_fence(input, syncobj.new_fence(71, 1))
		for count in [u32(65), 1025]! {
			records := sync_records(count, count, input.handle, input.handle, target.handle, target.handle)
			for _ in 0 .. 20 { measure_sync_storage(records, count) }
			for batch in 0 .. 3 {
				before_blocks, before_bytes := live_record_heap()
				for _ in 0 .. 1000 { measure_sync_storage(records, count) }
				after_blocks, after_bytes := live_record_heap()
				assert before_blocks == after_blocks && before_bytes == after_bytes
				println('large-sync count=${count} batch=${batch} operations=1000 retained_blocks=${i64(after_blocks) - before_blocks} retained_bytes=${i64(after_bytes) - i64(before_bytes)}')
			}
			unsafe { records.free() }
		}
	} $else {
		panic('malloc-zone retention measurement requires macOS')
	}
}

fn measure_sync_storage(records []asahi.Sync, count u32) {
	code, inputs, outputs := submission.stage_packet_syncs(1, u64(records.data), count, count)
	assert code == 0
	copy_code, copied := submission.copy_sync_array(unsafe { &inputs })
	assert copy_code == 0 && voidptr(copied.items) != voidptr(inputs.items)
	submission.release_sync_array(inputs)
	submission.release_sync_array(outputs)
	submission.release_sync_array(copied)
	assert memory.outstanding() == 0
}

pub fn run_large_sync_checks() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	input, gate, first, last := output(), output(), output(), output()
	base := syncobj.new_fence(71, 1)
	syncobj.signal(base)
	syncobj.replace_fence(input, base)
	compute := asahi.CmdCompute{}
	mut bytes := []u8{}
	bytes.flags |= .noslices
	defer { unsafe { bytes.free() } }
	append_packet(mut bytes, asahi.cmd_compute, unsafe { &compute }, u16(sizeof(compute)), asahi.barrier_none, asahi.barrier_none)
	mut cases := 0
	for inputs in [u32(0), 1, 63, 64, 65, 128, 129, 1025]! {
		for outputs in [u32(0), 1, 63, 64, 65, 128, 129, 1025]! {
			gpu.reset()
			dependency := syncobj.new_fence(72, u64(cases))
			syncobj.replace_fence(gate, dependency)
			mut records := sync_records(inputs, outputs, input.handle, gate.handle, first.handle, last.handle)
			code, staged_inputs, staged_outputs := submission.stage_packet_syncs(1, u64(records.data), inputs, outputs)
			assert code == 0, 'modern sync counts beyond 64 must be accepted'
			assert staged_inputs.count == inputs && staged_outputs.count == outputs
			assert memory.outstanding() == int(inputs > 64) + int(outputs > 64)
			for index := u32(0); index < inputs; index++ {
				item := staged_inputs.item(index)
				assert voidptr(item.fence) == voidptr(if index + 1 == inputs {
					dependency
				} else {
					base
				})
				assert item.timeline == (index + 1 == inputs) && item.timeline_value == 0
			}
			for index := u32(0); index < outputs; index++ {
				item := staged_outputs.item(index)
				assert voidptr(item.object) == voidptr(if index + 1 == outputs {
					last
				} else {
					first
				})
			}
			copy_code, copied := submission.copy_sync_array(unsafe { &staged_inputs })
			assert copy_code == 0 && copied.count == inputs
			if inputs > 64 {
				assert voidptr(copied.items) != voidptr(staged_inputs.items), 'pending dependency copy must own independent storage'
			}
			submission.release_sync_array(staged_inputs)
			submission.release_sync_array(staged_outputs)
			if inputs != 0 {
				assert voidptr(copied.item(inputs - 1).fence) == voidptr(dependency)
			}
			submission.release_sync_array(copied)
			assert memory.outstanding() == 0
			request := asahi.Submit{
				queue_id:       1
				syncs:          u64(records.data)
				in_sync_count:  inputs
				out_sync_count: outputs
				cmdbuf:         u64(bytes.data)
				cmdbuf_size:    u32(bytes.len)
			}
			assert file.ioctl_modern_submit(unsafe { &request }) == 0
			assert memory.outstanding() == 1 + int(inputs > 64), 'pending work owns its dynamic dependency copy'
			unsafe {
				C.memset(records.data, 0xff, records.len * int(sizeof(asahi.Sync)))
				records.free()
			}
			syncobj.replace_fence(gate, base)
			service_file_work()
			if inputs != 0 {
				assert manager.published.len == 0, 'last captured input must gate the large list'
				syncobj.signal(dependency)
				service_file_work()
			}
			assert manager.published == [u32(12)]
			manager.finish_compute(0)
			service_file_work()
			assert memory.outstanding() == 0, 'retired pending work must free dynamic dependency storage'
			if outputs != 0 {
				assert syncobj.is_signaled(fence(last)) && syncobj.get_error(fence(last)) == 0
				if outputs > 1 {
					assert voidptr(fence(first)) == voidptr(fence(last))
				}
			}
			assert_drained(file)
			cases++
		}
	}
	check_large_sync_failures(mut file, bytes, input, gate, first, last)
	check_large_sync_pointer_order(mut file)
	check_large_sync_backend_lifetimes(mut file, bytes, input, gate, first, last)
	assert cases == 64
	println('AGX large syncs: 64 input/output boundary pairs through staging/copy/pending retirement, counts through 1025, last-input waits, last-output publication, immutable snapshots and independent storage pass')
}

fn check_large_sync_failures(mut file GpuFile, bytes []u8, input &syncobj.SyncObj, gate &syncobj.SyncObj,
	first &syncobj.SyncObj, last &syncobj.SyncObj) {
	mut records := sync_records(65, 65, input.handle, gate.handle, first.handle, last.handle)
	defer { unsafe { records.free() } }
	request := asahi.Submit{
		queue_id:       1
		syncs:          u64(records.data)
		in_sync_count:  65
		out_sync_count: 65
		cmdbuf:         u64(bytes.data)
		cmdbuf_size:    u32(bytes.len)
	}
	mut cases := 0
	for _ in 0 .. 20 {
		for fail in 0 .. 7 {
			memory.fail_at(fail)
			assert file.ioctl_modern_submit(unsafe { &request }) == -12
			memory.fail_at(-1)
			assert memory.outstanding() == 0, 'failed submit must free dynamic sync storage'
			assert_drained(file)
			cases++
		}
		for fault in [0, 64, 65, 129, 130]! {
			usercopy.reject_at(fault)
			assert file.ioctl_modern_submit(unsafe { &request }) == -14
			usercopy.reject_at(-1)
			assert memory.outstanding() == 0, 'failed submit must free dynamic sync storage'
			assert_drained(file)
			cases++
		}
		for index in [0, 64, 65, 129]! {
			saved := records[index]
			records[index].handle = ~u32(0)
			assert file.ioctl_modern_submit(unsafe { &request }) == -2
			records[index] = saved
			assert_drained(file)
			cases++
		}
	}
	usercopy.reset_reads()
	overflow, _, _ := submission.stage_packet_syncs(1, u64(records.data), ~u32(0), 1)
	assert overflow == -75 && usercopy.reads() == 0 && memory.outstanding() == 0
	memory.fail_at(0)
	huge, _, _ := submission.stage_packet_syncs(1, u64(records.data), ~u32(0), 0)
	assert huge == -12 && usercopy.reads() == 0
	memory.fail_at(-1)
	legacy, _ := submission.stage_sync_array(1, 0, 65, true)
	assert legacy == -22
	assert cases == 320
	println('AGX large sync faults: 320 allocation/copy/lookup failures unwind storage and captures; checked count overflow precedes copying, huge allocations stay fallible, legacy limit stays 64')
}

fn check_large_sync_pointer_order(mut file GpuFile) {
	for in_count in [u32(64), 65]! {
		for out_count in [u32(64), 65]! {
			spans := int(in_count > 64) + int(out_count > 64)
			for pointer in [u64(0), ~u64(0) - 15]! {
				request := asahi.Submit{queue_id: 1, syncs: pointer, in_sync_count: in_count,
					out_sync_count: out_count}
				for fail in 0 .. spans + 1 {
					memory.fail_at(fail)
					usercopy.reset_reads()
					code := file.ioctl_modern_submit(unsafe { &request })
					if fail < spans {
						assert code == -12, 'sync storage allocation failure must precede an invalid pointer'
						assert memory.attempts() == fail + 1
					} else {
						assert code == -14 && memory.attempts() == spans
					}
					assert usercopy.reads() == 0
					assert_drained(file)
				}
			}
		}
	}
	memory.fail_at(-1)
	println('AGX sync pointers: null and wrapping pointers exercise allocation precedence and cleanup')
}

fn check_large_sync_backend_lifetimes(mut file GpuFile, bytes []u8, input &syncobj.SyncObj,
	gate &syncobj.SyncObj, first &syncobj.SyncObj, last &syncobj.SyncObj) {
	records := sync_records(65, 65, input.handle, gate.handle, first.handle, last.handle)
	defer { unsafe { records.free() } }
	request := asahi.Submit{
		queue_id:       1
		syncs:          u64(records.data)
		in_sync_count:  65
		out_sync_count: 65
		cmdbuf:         u64(bytes.data)
		cmdbuf_size:    u32(bytes.len)
	}
	mut cases := 0
	for _ in 0 .. 20 {
		for mode in 0 .. 7 {
			gpu.reset()
			mut manager := gpu.get_global_manager() or { panic('manager') }
			dependency := syncobj.new_fence(73, u64(cases))
			syncobj.replace_fence(gate, dependency)
			match mode {
				0 { manager.fail_compute = true }
				1 { manager.fail_compute_callback = true }
				2 { manager.fail_barrier_at = 0 }
				3 { manager.stop_callback_at = 0 }
				6 {
					manager.immediate_complete = true
					syncobj.signal(dependency)
				}
				else {}
			}
			code := file.ioctl_modern_submit(unsafe { &request })
			if mode < 4 {
				assert code < 0
			} else {
				assert code == 0 && memory.outstanding() == 2
				if mode == 4 {
					manager.stop()
				} else if mode == 5 {
					file.vm.detached = true
					file.queues[0] = LogicalQueue{ id: 1, detached: true }
					service_file_work()
					assert manager.published.len == 0 && memory.outstanding() == 2
					syncobj.signal(dependency)
				}
				service_file_work()
				if mode == 5 {
					manager.finish_compute(0)
					service_file_work()
				}
				assert syncobj.is_signaled(fence(last))
				assert syncobj.get_error(fence(last)) == if mode == 4 { -19 } else { 0 }
			}
			file.vm.detached = false
			file.queues[0] = LogicalQueue{ id: 1 }
			assert_drained(file)
			cases++
		}
	}
	assert cases == 140
	println('AGX large sync ownership: 140 prepare/barrier/callback/registration failures, stopped jobs, detached names and immediate completion cases release pending dependency storage exactly once')
}
