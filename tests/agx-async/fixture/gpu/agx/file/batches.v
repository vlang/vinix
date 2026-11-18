@[has_globals]
module file

import drm.gem
import drm.ioctl
import drm.syncobj
import gpu.agx.gpu
import gpu.agx.submission
import memory

__global notification_node &G13PendingSubmission = unsafe { nil }
__global notification_file &GpuFile = unsafe { nil }
__global notification_object &gem.GemObject = unsafe { nil }
__global notifications = 0

fn on_batch_notification(_ &syncobj.DmaFence) {
	assert notification_node.callbacks_remaining == 0
	assert notification_file.vm.inflight == 1
	if notification_object != unsafe { nil } {
		assert notification_object.references == 1
	}
	notifications++
}

fn watch_batch(file &GpuFile, object &gem.GemObject, target &syncobj.DmaFence) {
	notification_node = pending_head
	notification_file = unsafe { file }
	notification_object = unsafe { object }
	syncobj.add_waiter(target, &syncobj.FenceWaiter{ callback: on_batch_notification })
}

fn is_compute(index u32, pattern int) bool {
	return pattern == 0 || (pattern == 2 && index % 2 == 0) || (pattern == 3 && index % 2 == 1)
}

fn submit_batch(mut file GpuFile, count u32, pattern int, bad int,
	input &syncobj.SyncObj, output &syncobj.SyncObj, results bool) int {
	assert count <= 65
	compute := ioctl.DrmAsahiCmdCompute{ encoder_ptr: 0x12340000 }
	render := ioctl.DrmAsahiCmdRender{
		fb_width:     32
		fb_height:    32
		layers:       1
		utile_width:  32
		utile_height: 32
		samples:      1
	}
	mut commands := [65]ioctl.DrmAsahiCommand{}
	mut prior := [2]u32{}
	for index := u32(0); index < count; index++ {
		comp := is_compute(index, pattern)
		commands[index] = ioctl.DrmAsahiCommand{
			cmd_type:        if comp { ioctl.asahi_cmd_compute } else { ioctl.asahi_cmd_render }
			cmd_buffer:      if comp { u64(&compute) } else { u64(&render) }
			cmd_buffer_size: if comp { sizeof(compute) } else { sizeof(render) }
			barriers:        prior
			result_offset:   if results { u64(index) * 128 } else { 0 }
			result_size:     if !results {
				0
			} else if comp {
				sizeof(ioctl.DrmAsahiResultCompute)
			} else {
				sizeof(ioctl.DrmAsahiResultRender)
			}
		}
		prior[if comp { 1 } else { 0 }]++
	}
	if bad == 1 { commands[2].barriers[0] = 1 } // no prior render, despite two prior commands
	if bad == 2 { commands[0].barriers[1] = 1 } // future/self dependency
	if bad == 3 { commands[0].cmd_type = ioctl.asahi_cmd_blit }
	if bad == 4 { commands[63].cmd_buffer_size = 0 }
	in_sync := ioctl.DrmAsahiSync{ handle: if input != unsafe { nil } { input.handle } else { 0 } }
	out_sync := ioctl.DrmAsahiSync{ handle: if output != unsafe { nil } { output.handle } else { 0 } }
	request := ioctl.DrmAsahiSubmit{
		queue_id:       1
		commands:       if bad == 5 { ~u64(0) - 20 } else { unsafe { u64(&commands) } }
		command_count:  count
		result_handle:  if results { 7 } else { 0 }
		in_syncs:       u64(&in_sync)
		out_syncs:      u64(&out_sync)
		in_sync_count:  if input != unsafe { nil } { 1 } else { 0 }
		out_sync_count: if output != unsafe { nil } { 1 } else { 0 }
	}
	return file.ioctl_submit(&request)
}

fn check_full_batch(pattern int) {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	mut result := [8192]u8{}
	mut object := gem.GemObject{ size: sizeof(result), virt_addr: unsafe { u64(&result) } }
	file.objects = Objects{ object: &object }
	out := output()
	assert submit_batch(mut file, 64, pattern, 0, unsafe { nil }, out, true) == 0
	assert fence(out).seqno == 1 && file.g13_queues[0].resources.fence_seqno == 1
	assert file.vm.inflight == 65 && object.references == 65
	assert pending_count == 1 && memory.outstanding() == 1 && manager.published.len == 0
	before_notifications := notifications
	watch_batch(file, &object, fence(out))
	service_file_work()
	for index := u32(0); index < 64; index++ {
		assert manager.published.len == 64, 'firmware dependencies must not wait for CPU callbacks'
		assert manager.published[index] == if is_compute(index, pattern) {
			u32(12)
		} else {
			u32(10)
		}
		assert !syncobj.is_signaled(fence(out)), 'output must wait for the final command'
		if is_compute(index, pattern) {
			manager.finish_compute(0)
		} else {
			manager.finish_render(0)
		}
		assert object.references == 64 - int(index)
		if index != 63 {
			assert !syncobj.is_signaled(fence(out))
		}
		service_file_work()
	}
	assert syncobj.is_signaled(fence(out)) && syncobj.get_error(fence(out)) == 0
	assert notifications == before_notifications + 1
	for index := u32(0); index < 64; index++ {
		info := unsafe { &ioctl.DrmAsahiResultInfo(&result[index * 128]) }
		assert info.status == ioctl.asahi_status_complete
	}
	assert_drained(file)
}

fn assert_reverse(order []u32, count int) {
	assert order.len == count
	for index in 0 .. count {
		assert order[index] == u32(count - index - 1)
	}
}

fn check_batch_failures() {
	for mode in 0 .. 5 {
		for index in 0 .. 64 {
			gpu.reset()
			mut file := new_file()
			mut manager := gpu.get_global_manager() or { panic('manager') }
			manager.fail_prepare_at = if mode == 0 { index } else { -1 }
			manager.fail_callback_at = if mode == 1 { index } else { -1 }
			manager.stop_callback_at = if mode == 2 { index } else { -1 }
			manager.fail_barrier_at = if mode == 3 { index } else { -1 }
			manager.stop_barrier_at = if mode == 4 { index } else { -1 }
			out := output()
			assert submit_batch(mut file, 64, 2, 0, unsafe { nil }, out, false) < 0
			assert file.g13_queues[0].resources.fence_seqno == 0
			assert manager.published.len == 0
			assert_reverse(manager.released_order, if mode == 0 { index } else { 64 })
			assert_drained(file)
		}
	}
	for allocation in 0 .. 2 {
		gpu.reset()
		mut file := new_file()
		memory.fail_at(allocation)
		assert submit_batch(mut file, 64, 2, 0, unsafe { nil }, unsafe { nil }, false) == -12
		memory.fail_at(-1)
		assert_drained(file)
	}
	for bad in 1 .. 6 {
		gpu.reset()
		mut file := new_file()
		assert submit_batch(mut file, 64, 0, bad, unsafe { nil }, unsafe { nil }, false) < 0
		manager := gpu.get_global_manager() or { panic('manager') }
		assert manager.prepares == 0, 'all descriptors/barriers must be validated before GPU preparation'
		assert_drained(file)
	}
	for count in [u32(0), 65]! {
		gpu.reset()
		mut file := new_file()
		assert submit_batch(mut file, count, 2, 0, unsafe { nil }, unsafe { nil }, false) == -22
		assert_drained(file)
	}
}

fn check_middle_failure_and_shutdown() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	out := output()
	assert submit_batch(mut file, 64, 2, 0, unsafe { nil }, out, false) == 0
	before_notifications := notifications
	watch_batch(file, unsafe { nil }, fence(out))
	manager.publication_limit = 32
	service_file_work()
	for index := u32(0); index < 32; index++ {
		status := if index == 31 { u32(3) } else { u32(0) }
		if is_compute(index, 2) {
			manager.finish_compute(status)
		} else {
			manager.finish_render(status)
		}
		service_file_work()
	}
	assert manager.published.len == 32 && manager.released_order.len == 32
	assert manager.released_order[0] == 63 && manager.released_order[31] == 32
	assert syncobj.get_error(fence(out)) == -110
	assert notifications == before_notifications + 1
	assert_drained(file)
	gpu.reset()
	manager = gpu.get_global_manager() or { panic('manager') }
	stopped := output()
	assert submit_batch(mut file, 64, 3, 0, unsafe { nil }, stopped, false) == 0
	manager.publication_limit = 1
	service_file_work()
	manager.stop()
	service_file_work()
	assert manager.released_order.len == 63 && syncobj.get_error(fence(stopped)) == -19
	assert_drained(file)
}

fn check_unqueued_results() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	mut results := [8192]u8{}
	mut object := gem.GemObject{ size: sizeof(results), virt_addr: unsafe { u64(&results) } }
	file.objects = Objects{ object: &object }
	manager.stop_callback_at = 63
	out := output()
	previous := syncobj.new_fence(40, 1)
	syncobj.replace_fence(out, previous)
	before := notifications
	assert submit_batch(mut file, 64, 2, 0, unsafe { nil }, out, true) == -19
	assert notifications == before && object.references == 1
	assert voidptr(fence(out)) == voidptr(previous) && !syncobj.is_signaled(previous)
	assert file.g13_queues[0].resources.fence_seqno == 0
	assert_drained(file)
}

fn check_fake_pair_limit() {
	assert submission.max_commands == 64 && submission.max_legacy_commands == 2
	render := ioctl.DrmAsahiCmdRender{
		fb_width:     32
		fb_height:    32
		layers:       1
		utile_width:  32
		utile_height: 32
		samples:      1
	}
	compute := ioctl.DrmAsahiCmdCompute{}
	mut commands := [2]ioctl.DrmAsahiCommand{}
	commands[0] = ioctl.DrmAsahiCommand{
		cmd_type:        ioctl.asahi_cmd_compute
		cmd_buffer:      u64(&compute)
		cmd_buffer_size: sizeof(compute)
		barriers:        [ioctl.asahi_barrier_none, ioctl.asahi_barrier_none]!
	}
	commands[1] = ioctl.DrmAsahiCommand{
		cmd_type:        ioctl.asahi_cmd_render
		cmd_buffer:      u64(&render)
		cmd_buffer_size: sizeof(render)
		barriers:        [ioctl.asahi_barrier_none, u32(1)]!
	}
	code, _ := submission.stage_commands(unsafe { u64(&commands) }, 2)
	assert code == 0
	too_many, _ := submission.stage_commands(unsafe { u64(&commands) }, 3)
	assert too_many == -22
	commands[0], commands[1] = commands[1], commands[0]
	reversed, _ := submission.stage_commands(unsafe { u64(&commands) }, 2)
	assert reversed == -22
}

fn check_batches() {
	for pattern in 0 .. 4 { check_full_batch(pattern) }
	check_batch_failures()
	check_middle_failure_and_shutdown()
	check_fake_pair_limit()
	check_unqueued_results()
	check_legacy_timeline()
	println('AGX batches: four 64-command orderings, per-subqueue barrier bounds, final fence/results, all 64 prepare/barrier/callback/stop failure positions, both allocations, reverse unwind, middle failure and fake pair limit passed')
}
