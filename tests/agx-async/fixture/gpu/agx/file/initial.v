@[has_globals]
module file

import drm.syncobj
import errno
import event
import gpu.agx.gpu
import memory
import proc

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
	check_initial_capture_across_admission()
	println('AGX initial submissions: empty pipe, per-command prefix, immutable prior target, execution-before-callback, errored input with firmware ordering, rejected admission and capture setup/stop cleanup passed')
}

enum InitialCaptureWake {
	retire
	interrupt
	stop
	fail_storage
}

__global capture_wake InitialCaptureWake

fn retire_during_initial_capture_wait() {
	mut manager := gpu.get_global_manager() or { panic('manager') }
	assert !waiting_file.lock.is_held() && !manager.lock.is_held()
	assert manager.capture_pins == 1, 'the prior event must be captured before slot admission'
	if capture_wake == .stop {
		manager.stop()
	} else {
		assert manager.execute_firmware(0, 0)
		manager.retire_firmware(0)
	}
	service_file_work()
	assert manager.capture_pins == 1 && waiting_file.vm.inflight == 0
	if capture_wake == .interrupt {
		mut task := proc.current_thread()
		task.pending = 1
	}
	if capture_wake == .fail_storage { memory.fail_next(true) }
	uat_mgr.make_slot_available()
}

fn check_initial_capture_across_admission() {
	for modern in [false, true]! {
		for wake in [InitialCaptureWake.retire, .interrupt, .stop, .fail_storage]! {
			gpu.reset()
			mut file := new_file()
			mut manager := gpu.get_global_manager() or { panic('manager') }
			assert submit(mut file, 1, false, unsafe { nil }, unsafe { nil }, false) == 0
			service_file_work()
			out := output()
			previous := syncobj.new_fence(95, 1)
			syncobj.replace_fence(out, previous)
			waiting_file = file
			capture_wake = wake
			// Force pressure in the host allocator to exercise pin cleanup
			// while a preceding event exists, including device shutdown.
			uat_mgr.occupied = true
			event.before_wait(retire_during_initial_capture_wait, false)
			code := if modern {
				submit_slot_wait_packet(mut file, 1, 0, out)
			} else {
				submit_scheduled(mut file, [ScheduledCommand{compute: true, compute_barrier: 0}], out, false)
			}
			memory.fail_next(false)
			mut task := proc.current_thread()
			task.pending = 0
			expected := match wake {
				.retire { 0 }
				.interrupt { -int(errno.erestartsys) }
				.stop { -19 }
				.fail_storage { -12 }
			}
			assert code == expected && manager.capture_pins == 0
			if expected == 0 {
				assert manager.g13_compute_jobs[0].initial_sources[1] == 1
				service_file_work()
				assert manager.execute_firmware(1, 0)
				manager.retire_firmware(1)
				service_file_work()
				assert syncobj.is_signaled(fence(out))
			} else {
				assert voidptr(fence(out)) == voidptr(previous)
			}
			assert_drained(file)
			waiting_file = unsafe { nil }
		}
	}
	println('G13 prior events: pre-bind snapshot survives injected retirement, interruption, shutdown and pending OOM through both submit ABIs')
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
