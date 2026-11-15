module file

import drm.gem
import drm.syncobj
import gpu.agx.gpu
import katomic

fn check_firmware_chains() {
	// Both directions, all-same-pipe and alternating chains. Complete GPU work
	// before any CPU callback, then deliver callbacks in reverse order.
	for pattern in 0 .. 4 {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		mut results := [8192]u8{}
		mut object := gem.GemObject{ size: sizeof(results), virt_addr: unsafe { u64(&results) } }
		file.objects = Objects{ object: &object }
		out := output()
		assert submit_batch(mut file, 64, pattern, 0, unsafe { nil }, out, true) == 0
		watch_batch(file, &object, fence(out))
		service_file_work()
		assert manager.published.len == 64 && pending_head.callbacks_remaining == 64
		for index := u32(63); index > 0; index-- {
			assert !manager.execute_firmware(index, 0), 'a firmware dependency must block execution'
		}
		for index := u32(0); index < 64; index++ {
			assert manager.execute_firmware(index, 0)
			service_file_work()
			assert pending_head.callbacks_remaining == 64 && object.references == 65
			assert !syncobj.is_signaled(fence(out)), 'firmware execution is not CPU retirement'
		}
		for index := 63; index >= 0; index-- {
			manager.retire_firmware(u32(index))
			service_file_work()
			if index > 0 {
				assert !syncobj.is_signaled(fence(out))
			}
		}
		assert syncobj.is_signaled(fence(out)) && syncobj.get_error(fence(out)) == 0
		assert_drained(file)
	}
}

fn check_firmware_fragment_and_older_target() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	out := output()
	assert submit_scheduled(mut file, [ScheduledCommand{}, ScheduledCommand{},
		ScheduledCommand{ compute: true, render_barrier: 1 }], out, false) == 0
	service_file_work()
	assert manager.published_order == [u32(0), 1, 2]
	assert manager.execute_vertex(0)
	assert !manager.execute_firmware(2, 0), 'vertex completion cannot satisfy a render dependency'
	assert manager.execute_firmware(0, 0)
	assert manager.execute_firmware(2, 0), 'the first render is sufficient; do not wait for the second'
	manager.retire_firmware(2)
	service_file_work()
	assert !syncobj.is_signaled(fence(out)) && file.inflight_by_vm[1] == 3
	assert manager.execute_firmware(1, 0)
	manager.retire_firmware(1)
	service_file_work()
	assert !syncobj.is_signaled(fence(out))
	manager.retire_firmware(0)
	service_file_work()
	assert_drained(file)
}

fn check_published_dependency_failure() {
	// A producer callback cannot cancel/free consumers already owned by the
	// manager. Their firmware completion (or firmware stop) still owns teardown.
	for stop in [false, true]! {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		out := output()
		assert submit_scheduled(mut file, [ScheduledCommand{ compute: true },
			ScheduledCommand{ compute_barrier: 1 },
			ScheduledCommand{ compute: true, render_barrier: 1 },
			ScheduledCommand{ compute_barrier: 2 }], out, false) == 0
		watch_batch(file, unsafe { nil }, fence(out))
		service_file_work()
		assert manager.published.len == 4
		assert manager.execute_firmware(0, 3)
		manager.retire_firmware(0)
		service_file_work()
		assert manager.released_order.len == 0 && pending_head.callbacks_remaining == 3
		assert file.inflight_by_vm[1] == 4 && !syncobj.is_signaled(fence(out))
		if stop {
			manager.stop()
		} else {
			for index := u32(1); index < 4; index++ {
				assert manager.execute_firmware(index, 5)
				manager.retire_firmware(index)
				service_file_work()
				if index < 3 {
					assert !syncobj.is_signaled(fence(out))
				}
			}
		}
		service_file_work()
		assert syncobj.get_error(fence(out)) == -110
		assert_drained(file)
	}
}

fn check_firmware_dependencies() {
	check_firmware_chains()
	check_firmware_fragment_and_older_target()
	check_published_dependency_failure()
	check_stop_during_dependency_publication()
	check_stop_at_final_callback_load()
	println('AGX firmware scheduling: four full dependency chains publish before callbacks; injected firmware gates execution, waits for fragment/older targets, and retains failed consumers until completion or stop')
}

__global stop_at_count &G13PendingSubmission = unsafe { nil }

fn stop_before_count_load(address voidptr) {
	if address != voidptr(&stop_at_count.callbacks_remaining) { return }
	katomic.set_load_hook(unsafe { nil })
	mut manager := gpu.get_global_manager() or { panic('manager') }
	manager.stop()
}

fn check_stop_at_final_callback_load() {
	// The shutdown state changes after the last ordinary state check and
	// immediately before acquiring zero callbacks. Unpublished metadata remains.
	for pattern in 0 .. 4 {
		for limit in [0, 1, 31, 63]! {
			gpu.reset()
			mut file := new_file()
			mut manager := gpu.get_global_manager() or { panic('manager') }
			manager.publication_limit = limit
			out := output()
			assert submit_batch(mut file, 64, pattern, 0, unsafe { nil }, out, false) == 0
			watch_batch(file, unsafe { nil }, fence(out))
			stop_at_count = pending_head
			katomic.set_load_hook(stop_before_count_load)
			service_file_work()
			katomic.set_load_hook(unsafe { nil })
			stop_at_count = unsafe { nil }
			assert manager.published.len == limit
			assert manager.released_order.len == 64 - limit
			assert syncobj.get_error(fence(out)) == -19
			assert_drained(file)
		}
	}
	println('AGX final callback acquisition: 16 shutdown/count-load interleavings release prepared pointers before node retirement')
}

fn check_stop_during_dependency_publication() {
	for pattern in 0 .. 4 {
		for after_publish in [false, true]! {
			for index in 0 .. 64 {
				gpu.reset()
				mut file := new_file()
				mut manager := gpu.get_global_manager() or { panic('manager') }
				manager.stop_publish_at = if after_publish { index } else { -1 }
				manager.stop_submit_at = if after_publish { -1 } else { index }
				out := output()
				assert submit_batch(mut file, 64, pattern, 0, unsafe { nil }, out, false) == 0
				watch_batch(file, unsafe { nil }, fence(out))
				service_file_work()
				assert manager.published.len == index + if after_publish { 1 } else { 0 }
				assert manager.released_order.len == 64 - manager.published.len
				assert syncobj.get_error(fence(out)) == -19
				assert_drained(file)
			}
		}
	}
	println('AGX publication shutdown: before/after each of 64 commands in four dependency-chain orderings cleans caller-owned metadata after stop (512 cases)')
}
