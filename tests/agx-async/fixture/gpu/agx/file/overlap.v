@[has_globals]
module file

import drm.gem
import drm.ioctl
import drm.syncobj
import gpu.agx.gpu

struct ScheduledCommand {
	compute         bool
	render_barrier  u32 = ioctl.asahi_barrier_none
	compute_barrier u32 = ioctl.asahi_barrier_none
}

fn submit_scheduled(mut file GpuFile, schedule []ScheduledCommand, out &syncobj.SyncObj, results bool) int {
	assert schedule.len > 0 && schedule.len <= 64
	compute := ioctl.DrmAsahiCmdCompute{ encoder_ptr: 0x12340000 }
	render := ioctl.DrmAsahiCmdRender{
		fb_width:     32
		fb_height:    32
		layers:       1
		utile_width:  32
		utile_height: 32
		samples:      1
	}
	mut commands := [64]ioctl.DrmAsahiCommand{}
	for index, entry in schedule {
		commands[index] = ioctl.DrmAsahiCommand{
			cmd_type:        if entry.compute {
				ioctl.asahi_cmd_compute
			} else {
				ioctl.asahi_cmd_render
			}
			cmd_buffer:      if entry.compute { u64(&compute) } else { u64(&render) }
			cmd_buffer_size: if entry.compute { sizeof(compute) } else { sizeof(render) }
			barriers:        [entry.render_barrier, entry.compute_barrier]!
			result_offset:   if results { u64(index) * 128 } else { 0 }
			result_size:     if !results {
				0
			} else if entry.compute {
				sizeof(ioctl.DrmAsahiResultCompute)
			} else {
				sizeof(ioctl.DrmAsahiResultRender)
			}
		}
	}
	out_sync := ioctl.DrmAsahiSync{ handle: out.handle }
	request := ioctl.DrmAsahiSubmit{
		queue_id:       1
		commands:       unsafe { u64(&commands) }
		command_count:  u32(schedule.len)
		result_handle:  if results { 7 } else { 0 }
		out_syncs:      u64(&out_sync)
		out_sync_count: 1
	}
	return file.ioctl_submit(&request)
}

fn check_independent_completion_orders() {
	for compute_first in [true, false]! {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		mut results := [256]u8{}
		mut object := gem.GemObject{ size: sizeof(results), virt_addr: unsafe { u64(&results) } }
		file.objects = Objects{ object: &object }
		out := output()
		assert submit_scheduled(mut file, [ScheduledCommand{}, ScheduledCommand{ compute: true }], out, true) == 0
		watch_batch(file, &object, fence(out))
		service_file_work()
		assert manager.published_order == [u32(0), 1]
		assert file.inflight_by_vm[1] == 3 && object.references == 3
		if compute_first { manager.finish_compute(0) } else { manager.finish_render(0) }
		service_file_work()
		assert !syncobj.is_signaled(fence(out)) && file.inflight_by_vm[1] == 2 && object.references == 2
		if compute_first { manager.finish_render(0) } else { manager.finish_compute(0) }
		service_file_work()
		assert syncobj.is_signaled(fence(out)) && syncobj.get_error(fence(out)) == 0
		assert_drained(file)
	}
}

fn check_subqueue_dependencies() {
	// A render head waits for compute #1. Its successor cannot pass it,
	// while the second compute can publish and have its callback run first.
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	out := output()
	assert submit_scheduled(mut file, [ScheduledCommand{ compute: true },
		ScheduledCommand{ compute_barrier: 1 }, ScheduledCommand{}, ScheduledCommand{ compute: true }], out, false) == 0
	service_file_work()
	assert manager.published_order == [u32(0), 3]
	manager.finish_compute_at(3, 0)
	service_file_work()
	assert manager.published_order == [u32(0), 3]
	manager.finish_compute_at(0, 0)
	service_file_work()
	assert manager.published_order == [u32(0), 3, 1, 2]
	manager.finish_render_at(2, 0)
	service_file_work()
	assert !syncobj.is_signaled(fence(out))
	manager.finish_render_at(1, 0)
	service_file_work()
	assert_drained(file)
	// Index one names the first compute, not the latest preceding compute.
	gpu.reset()
	manager = gpu.get_global_manager() or { panic('manager') }
	nth := output()
	assert submit_scheduled(mut file, [ScheduledCommand{ compute: true },
		ScheduledCommand{ compute: true }, ScheduledCommand{ compute_barrier: 1 }], nth, false) == 0
	service_file_work()
	assert manager.published_order == [u32(0), 1]
	manager.finish_compute_at(0, 0)
	service_file_work()
	assert manager.published_order == [u32(0), 1, 2]
	manager.finish_render_at(2, 0)
	service_file_work()
	assert !syncobj.is_signaled(fence(nth))
	manager.finish_compute_at(1, 0)
	service_file_work()
	assert_drained(file)
	// Render dependencies require the full render callback, including fragment.
	gpu.reset()
	manager = gpu.get_global_manager() or { panic('manager') }
	reverse := output()
	assert submit_scheduled(mut file, [ScheduledCommand{},
		ScheduledCommand{ compute: true, render_barrier: 1 }, ScheduledCommand{}], reverse, false) == 0
	service_file_work()
	assert manager.published_order == [u32(0), 2]
	manager.finish_render_at(2, 0)
	service_file_work()
	assert manager.published_order == [u32(0), 2]
	manager.finish_render_at(0, 0)
	service_file_work()
	assert manager.published_order == [u32(0), 2, 1]
	manager.finish_compute(0)
	service_file_work()
	assert_drained(file)
}

__global race_job &gpu.G13RenderJobResources = unsafe { nil }

fn quarantine_during_submit() {
	unsafe { race_job.quarantined = true }
}

fn check_pipe_backpressure_and_quarantine() {
	for compute_blocked in [true, false]! {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		out := output()
		assert submit_scheduled(mut file, [
			ScheduledCommand{ compute: compute_blocked },
			ScheduledCommand{ compute: compute_blocked },
			ScheduledCommand{ compute: !compute_blocked },
		], out, false) == 0
		manager.compute_ring_full = compute_blocked
		manager.render_ring_full = !compute_blocked
		service_file_work()
		assert manager.published_order == [u32(2)]
		manager.compute_ring_full = false
		manager.render_ring_full = false
		service_file_work()
		assert manager.published_order == [u32(2), 0, 1]
		for _ in 0 .. 2 {
			if compute_blocked { manager.finish_compute(0) } else { manager.finish_render(0) }
		}
		if compute_blocked { manager.finish_render(0) } else { manager.finish_compute(0) }
		service_file_work()
		assert_drained(file)
	}
	// Inject quarantine after the public poll guard, at the submission boundary.
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	out := output()
	assert submit_scheduled(mut file, [ScheduledCommand{ compute: true }, ScheduledCommand{}], out, false) == 0
	race_job = manager.g13_render_jobs[0]
	manager.on_submit = quarantine_during_submit
	service_file_work()
	assert manager.published.len == 0
	unsafe { race_job.quarantined = false }
	service_file_work()
	assert manager.published_order == [u32(0), 1]
	unsafe { race_job.quarantined = true }
	assert manager.g13_queue_dispatch_blocked(manager.g13_render_jobs[0].queue)
	unsafe { race_job.quarantined = false }
	manager.finish_compute(0)
	manager.finish_render(0)
	service_file_work()
	race_job = unsafe { nil }
	assert_drained(file)
}

fn check_overlap_failure_and_shutdown() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	out := output()
	assert submit_scheduled(mut file, [ScheduledCommand{ compute: true }, ScheduledCommand{},
		ScheduledCommand{ compute: true, render_barrier: 1 }, ScheduledCommand{ compute_barrier: 1 }], out, false) == 0
	watch_batch(file, unsafe { nil }, fence(out))
	service_file_work()
	assert manager.published_order == [u32(0), 1]
	manager.finish_compute(3)
	service_file_work()
	assert manager.released_order == [u32(3), 2]
	assert !syncobj.is_signaled(fence(out)) && file.inflight_by_vm[1] == 2
	manager.finish_render(0)
	service_file_work()
	assert syncobj.get_error(fence(out)) == -110
	assert_drained(file)
	for pattern in 0 .. 4 {
		gpu.reset()
		manager = gpu.get_global_manager() or { panic('manager') }
		mut schedule := []ScheduledCommand{len: 64}
		for index in 0 .. 64 {
			schedule[index] = ScheduledCommand{ compute: is_compute(u32(index), pattern) }
		}
		stopped := output()
		assert submit_scheduled(mut file, schedule, stopped, false) == 0
		service_file_work()
		assert manager.published.len == 64
		manager.stop()
		service_file_work()
		assert syncobj.get_error(fence(stopped)) == -19
		assert_drained(file)
	}
}

fn check_full_overlap_and_immediate_callbacks() {
	for pattern in 0 .. 4 {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		mut schedule := []ScheduledCommand{len: 64}
		for index in 0 .. 64 {
			schedule[index] = ScheduledCommand{ compute: is_compute(u32(index), pattern) }
		}
		out := output()
		assert submit_scheduled(mut file, schedule, out, false) == 0
		watch_batch(file, unsafe { nil }, fence(out))
		service_file_work()
		assert manager.published.len == 64
		for index := 63; index >= 0; index-- {
			assert manager.published_order[index] == u32(index)
			if is_compute(u32(index), pattern) {
				manager.finish_compute_at(u32(index), 0)
			} else {
				manager.finish_render_at(u32(index), 0)
			}
			if index != 0 {
				service_file_work()
				assert !syncobj.is_signaled(fence(out))
			}
		}
		service_file_work()
		assert syncobj.is_signaled(fence(out))
		assert_drained(file)
	}
	// A synchronous last callback must publish its error before aggregate signal.
	for failed_index in [-1, 0, 63]! {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		manager.immediate_complete = true
		manager.immediate_fault_at = failed_index
		mut schedule := []ScheduledCommand{len: 64}
		for index in 0 .. 64 { schedule[index] = ScheduledCommand{ compute: index % 2 == 0 } }
		out := output()
		assert submit_scheduled(mut file, schedule, out, false) == 0
		service_file_work()
		assert syncobj.is_signaled(fence(out)) && syncobj.get_error(fence(out)) == if failed_index == -1 {
			0
		} else {
			-110
		}
		assert manager.published.len == if failed_index == 0 { 1 } else { 64 }
		assert_drained(file)
	}
}

fn check_overlap() {
	check_independent_completion_orders()
	check_subqueue_dependencies()
	check_pipe_backpressure_and_quarantine()
	check_overlap_failure_and_shutdown()
	check_full_overlap_and_immediate_callbacks()
	println('AGX overlap: independent completion orders, subqueue-local dependencies/FIFO/backpressure, quarantine race, partial fault, four full 64-command reverse-callback batches, shutdown and immediate callbacks passed')
}
