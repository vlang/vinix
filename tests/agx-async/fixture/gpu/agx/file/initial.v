module file

import drm.syncobj
import gpu.agx.gpu

fn check_initial_submission_events() {
	// An empty compute subqueue must not wait for unrelated render retirement.
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	a, b := output(), output()
	assert submit_scheduled(mut file, [ScheduledCommand{}], a, false) == 0
	assert submit_scheduled(mut file, [ScheduledCommand{ compute: true, compute_barrier: 0 }], b, false) == 0
	service_file_work()
	assert manager.published_order == [u32(0), 1] && manager.execute_firmware(1, 0)
	manager.retire_firmware(1)
	service_file_work()
	assert syncobj.is_signaled(fence(b)) && !syncobj.is_signaled(fence(a))
	manager.stop()
	service_file_work()
	assert_drained(file)
	// Only the later command in the batch waits for the captured compute.
	// A still newer accepted compute cannot change that immutable target.
	gpu.reset()
	manager = gpu.get_global_manager() or { panic('manager') }
	older, batch, future := output(), output(), output()
	assert submit_scheduled(mut file, [ScheduledCommand{ compute: true }], older, false) == 0
	assert submit_scheduled(mut file, [ScheduledCommand{}, ScheduledCommand{ compute_barrier: 0 }], batch, false) == 0
	assert submit_scheduled(mut file, [ScheduledCommand{ compute: true }], future, false) == 0
	service_file_work()
	assert manager.published_order == [u32(0), 1, 2, 3]
	assert manager.g13_render_jobs[0].initial_sources == [u32(0), 0]!
	assert manager.g13_render_jobs[1].initial_sources == [u32(0), 1]!
	assert manager.execute_firmware(1, 0) && !manager.execute_firmware(2, 0)
	assert manager.execute_firmware(0, 0) && manager.execute_firmware(2, 0)
	// GPU execution, rather than the producer callback, releases the consumer.
	manager.retire_firmware(2)
	manager.retire_firmware(1)
	service_file_work()
	assert syncobj.is_signaled(fence(batch)) && !syncobj.is_signaled(fence(older))
	assert !syncobj.is_signaled(fence(future))
	assert manager.execute_firmware(3, 0)
	manager.retire_firmware(3)
	manager.retire_firmware(0)
	service_file_work()
	assert_drained(file)
	// An errored input releases the source, while its consumer still waits for
	// the captured firmware event rather than inheriting the input error.
	gpu.reset()
	manager = gpu.get_global_manager() or { panic('manager') }
	input, failed, consumer := output(), output(), output()
	dependency := syncobj.new_fence(1, 1)
	syncobj.replace_fence(input, dependency)
	assert submit(mut file, 1, false, input, failed, false) == 0
	assert submit_scheduled(mut file, [ScheduledCommand{ compute_barrier: 0 }], consumer, false) == 0
	service_file_work()
	assert manager.published.len == 0
	syncobj.signal_error(dependency, -110)
	service_file_work()
	assert manager.published_order == [u32(0), 1] && manager.g13_render_jobs[0].barrier_sources == [
		u32(0),
		1,
	]!
	assert !manager.execute_firmware(1, 0)
	assert manager.execute_firmware(0, 0)
	assert manager.execute_firmware(1, 0)
	manager.retire_firmware(1)
	service_file_work()
	assert !syncobj.is_signaled(fence(failed)) && syncobj.get_error(fence(consumer)) == 0
	manager.retire_firmware(0)
	service_file_work()
	assert syncobj.is_signaled(fence(failed)) && syncobj.get_error(fence(failed)) == 0
	assert_drained(file)
	// Failed ioctls must not replace the last accepted event marker.
	gpu.reset()
	manager = gpu.get_global_manager() or { panic('manager') }
	kept, rejected, later := output(), output(), output()
	assert submit_scheduled(mut file, [ScheduledCommand{ compute: true }], kept, false) == 0
	manager.fail_callback_at = 64
	assert submit_batch(mut file, 64, 2, 0, unsafe { nil }, rejected, false) == -5
	manager.fail_callback_at = -1
	assert submit_scheduled(mut file, [ScheduledCommand{ compute_barrier: 0 }], later, false) == 0
	service_file_work()
	assert manager.g13_render_jobs[0].initial_sources[1] == 1
	assert !manager.execute_firmware(65, 0)
	assert manager.execute_firmware(0, 0) && manager.execute_firmware(65, 0)
	manager.retire_firmware(65)
	manager.retire_firmware(0)
	service_file_work()
	assert_drained(file)
	check_initial_capture_setup_failures()
	println('AGX initial submissions: empty pipe, per-command prefix, immutable prior target, execution-before-callback, errored input with firmware ordering, rejected admission and capture setup/stop cleanup passed')
}

fn check_initial_capture_setup_failures() {
	for mode in 0 .. 5 {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		assert submit(mut file, 1, false, unsafe { nil }, unsafe { nil }, false) == 0
		manager.fail_prepare_at = if mode == 0 { 1 } else { -1 }
		manager.fail_barrier_at = if mode == 1 { 1 } else { -1 }
		manager.fail_callback_at = if mode == 2 { 1 } else { -1 }
		manager.stop_barrier_at = if mode == 3 { 1 } else { -1 }
		manager.stop_callback_at = if mode == 4 { 1 } else { -1 }
		assert submit_scheduled(mut file, [ScheduledCommand{ compute_barrier: 0 }], output(), false) < 0
		assert manager.capture_pins == 0
		manager.stop()
		service_file_work()
		assert_drained(file)
	}
}
