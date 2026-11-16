// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module file

import drm.gem
import drm.ioctl
import drm.syncobj
import gpu.agx.gpu
import memory
import usercopy

__global lookup_file &GpuFile = unsafe { nil }

fn remove_queue_during_copy() {
	// Copying must run after the probe released file.lock. No borrowed queue
	// pointer from that probe may be used by the later backend path.
	lookup_file.lock.acquire()
	lookup_file.queues[0] = LogicalQueue{ id: 3 }
	lookup_file.lock.release()
}

fn check_submission_lookup_order() {
	gpu.reset()
	mut file := new_file()
	manager := gpu.get_global_manager() or { panic('manager') }
	input := output(); output_obj := output(); old := syncobj.new_fence(99, 1)
	syncobj.replace_fence(input, old); syncobj.replace_fence(output_obj, old)
	mut bytes := [8192]u8{init: 0xa5}
	mut result := gem.GemObject{ size: sizeof(bytes), virt_addr: unsafe { u64(&bytes) } }
	file.objects = Objects{ object: unsafe { &result } }
	mut cases := 0
	for _ in 0 .. 200 {
		for queue in [u32(0), 3, 64, ~u32(0)]! {
			for failure in 0 .. 6 {
				mut payload := ioctl.DrmAsahiCmdCompute{}
				mut command := ioctl.DrmAsahiCommand{
					cmd_type: ioctl.asahi_cmd_compute, cmd_buffer: unsafe { u64(&payload) },
					cmd_buffer_size: sizeof(payload), result_size: sizeof(ioctl.DrmAsahiResultCompute),
					barriers: [ioctl.asahi_barrier_none, ioctl.asahi_barrier_none]!
				}
				mut in_sync := ioctl.DrmAsahiSync{ handle: input.handle }
				out_sync := ioctl.DrmAsahiSync{ handle: output_obj.handle }
				request := ioctl.DrmAsahiSubmit{
					queue_id: queue, commands: unsafe { u64(&command) }, command_count: 1,
					in_syncs: unsafe { u64(&in_sync) }, in_sync_count: 1,
					out_syncs: unsafe { u64(&out_sync) }, out_sync_count: 1, result_handle: 7
				}
				memory.fail_at(if failure == 0 { 0 } else { -1 })
				usercopy.reject(failure == 1)
				if failure == 2 { command.flags = 1 }
				if failure == 3 { payload.flags = ~u64(0) }
				if failure == 4 { in_sync.sync_type = ~u32(0) }
				if failure == 5 { in_sync.handle = ~u32(0) }
				usercopy.reset_reads()
				assert file.ioctl_submit(&request) == -2, 'queue lookup must precede staging failures'
				assert memory.attempts() == 0 && usercopy.reads() == 0
				cases++
			}
			for invalid in 0 .. 9 {
				mut request := ioctl.DrmAsahiSubmit{ queue_id: queue, commands: 1, command_count: 1,
					in_syncs: 1, in_sync_count: 1, out_syncs: 1, out_sync_count: 1 }
				match invalid {
					0 { request.extensions = 1 }
					1 { request.flags = 1 }
					2 { request.command_count = 0 }
					3 { request.command_count = 65 }
					4 { request.commands = 0 }
					5 { request.in_sync_count = 65 }
					6 { request.out_sync_count = 65 }
					7 { request.in_syncs = 0 }
					else { request.out_syncs = 0 }
				}
				memory.fail_at(0); usercopy.reject(true); usercopy.reset_reads()
				assert file.ioctl_submit(&request) == -22
				assert memory.attempts() == 0 && usercopy.reads() == 0
				cases++
			}
		}
		memory.fail_at(0); usercopy.reject(false)
		assert submit(mut file, 1, false, unsafe { nil }, output_obj, true) == -12; cases++
		memory.fail_at(-1); usercopy.reject(true)
		assert submit(mut file, 1, false, unsafe { nil }, output_obj, true) == -14; cases++
		usercopy.reject(false); memory.fail_at(-1); usercopy.reset_reads()
		lookup_file = file
		usercopy.before_once(remove_queue_during_copy)
		assert submit(mut file, 1, false, unsafe { nil }, output_obj, true) == 0
		assert usercopy.reads() > 0 && file.g13_queues[0].resources.has_file_references()
		service_file_work()
		mut active := unsafe { manager }
		active.finish_compute(0)
		service_file_work()
		assert syncobj.is_signaled(fence(output_obj))
		written := unsafe { &ioctl.DrmAsahiResultCompute(&bytes) }
		assert written.ts_start == 11 && written.ts_end == 22
		active.published.clear()
		syncobj.replace_fence(output_obj, old)
		for i in 0 .. bytes.len { bytes[i] = 0xa5 }
		lookup_file = unsafe { nil }; file.queues[0] = LogicalQueue{ id: 1 }; cases++
		assert_drained(file)
		assert manager.published.len == 0 && result.references == 1
		assert voidptr(fence(output_obj)) == voidptr(old) && !syncobj.is_signaled(old)
		for value in bytes { assert value == 0xa5 }
	}
	file.objects = Objects{}
	println('AGX submission lookup order: ${cases} checks; missing queues precede command OOM, copies, malformed descriptors/payloads and sync lookup; header validation retains precedence; retained snapshots survive namespace removal during unlocked copying')
}
