module file

import drm.ioctl
import drm.syncobj
import gpu.agx.gpu

fn check_queue_fence_elision() {
	// Earlier scenarios have drained their jobs. Retire their handle namespace
	// before extending the suite; preserve the production 1024-object limit and
	// retained fence allocations instead of expanding/resetting the table.
	assert pending_head == unsafe { nil } && pending_count == 0
	syncobj.destroy_owner(1)
	for stop in [false, true]! {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		a, b, foreign := output(), output(), output()
		assert submit(mut file, 1, false, unsafe { nil }, a, false) == 0
		assert submit_scheduled_with_input(mut file, 1, [ScheduledCommand{}], a, b, false) == 0
		assert submit(mut file, 2, false, a, foreign, false) == 0
		service_file_work()
		assert manager.published_order == [u32(0), 1], 'only the originating queue elides its input fence'
		assert !syncobj.is_signaled(fence(a)) && !syncobj.is_signaled(fence(b))
		if stop {
			manager.stop()
			service_file_work()
			assert syncobj.get_error(fence(a)) == -19 && syncobj.get_error(fence(b)) == -19
			assert syncobj.get_error(fence(foreign)) == -19
		} else {
			// Independent later work can finish first without signaling its producer.
			assert manager.execute_firmware(1, 0)
			manager.retire_firmware(1)
			service_file_work()
			assert syncobj.is_signaled(fence(b)) && !syncobj.is_signaled(fence(a))
			assert manager.published_order == [u32(0), 1]
			assert manager.execute_firmware(0, 3)
			manager.retire_firmware(0)
			service_file_work()
			assert syncobj.get_error(fence(a)) == -110 && syncobj.get_error(fence(b)) == 0
			assert manager.published_order == [u32(0), 1, 2]
			assert manager.execute_firmware(2, 0)
			manager.retire_firmware(2)
			service_file_work()
			assert syncobj.get_error(fence(foreign)) == 0
		}
		assert_drained(file)
	}
	check_elision_keeps_publication_and_firmware_order()
	check_recreated_queue_keeps_old_wait()
	check_elision_with_external_input()
	println('AGX queue fences: same-queue elision, foreign waits, reverse retirement, own errors/stop, partial publication, firmware prefixes and recreated-handle identity passed')
}

fn check_elision_with_external_input() {
	for own_first in [false, true]! {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		a, external, b := output(), output(), output()
		external_fence := syncobj.new_fence(1, 1)
		syncobj.replace_fence(external, external_fence)
		assert submit(mut file, 1, false, unsafe { nil }, a, false) == 0
		inputs := [ioctl.DrmAsahiSync{ handle: if own_first { a.handle } else { external.handle } },
			ioctl.DrmAsahiSync{ handle: if own_first { external.handle } else { a.handle } }]!
		out_sync := ioctl.DrmAsahiSync{ handle: b.handle }
		render := ioctl.DrmAsahiCmdRender{ fb_width: 32, fb_height: 32, layers: 1,
			utile_width: 32, utile_height: 32, samples: 1 }
		command := ioctl.DrmAsahiCommand{ cmd_type: ioctl.asahi_cmd_render,
			cmd_buffer: u64(&render), cmd_buffer_size: sizeof(render),
			barriers: [ioctl.asahi_barrier_none, ioctl.asahi_barrier_none]! }
		request := ioctl.DrmAsahiSubmit{ queue_id: 1, commands: u64(&command), command_count: 1,
			in_syncs: unsafe { u64(&inputs) }, in_sync_count: 2,
			out_syncs: u64(&out_sync), out_sync_count: 1 }
		assert file.ioctl_submit(&request) == 0
		service_file_work()
		assert manager.published_order == [u32(0)] && !syncobj.is_signaled(fence(b))
		syncobj.signal_error(external_fence, -5)
		service_file_work()
		assert manager.published_order == [u32(0), 1] && !syncobj.is_signaled(fence(a))
		assert manager.execute_firmware(1, 0)
		manager.retire_firmware(1)
		assert manager.execute_firmware(0, 0)
		manager.retire_firmware(0)
		service_file_work()
		assert syncobj.get_error(fence(b)) == 0
		assert_drained(file)
	}
}

fn check_elision_keeps_publication_and_firmware_order() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	a, b := output(), output()
	assert submit(mut file, 1, false, unsafe { nil }, a, false) == 0
	assert submit_scheduled_with_input(mut file, 1, [ScheduledCommand{ compute_barrier: 0 }], a, b, false) == 0
	manager.compute_ring_full = true
	service_file_work()
	assert manager.published.len == 0, 'elision cannot bypass older unpublished work'
	manager.compute_ring_full = false
	service_file_work()
	assert manager.published_order == [u32(0), 1] && !manager.execute_firmware(1, 0)
	assert manager.execute_firmware(0, 0) && manager.execute_firmware(1, 0)
	manager.retire_firmware(1)
	service_file_work()
	assert syncobj.is_signaled(fence(b)) && !syncobj.is_signaled(fence(a))
	manager.retire_firmware(0)
	service_file_work()
	assert_drained(file)
	// A matching public context/seqno on a generic fence does not elide it.
	gpu.reset()
	manager = gpu.get_global_manager() or { panic('manager') }
	input, out := output(), output()
	generic := syncobj.new_fence(fence(a).context, fence(a).seqno)
	syncobj.replace_fence(input, generic)
	assert submit(mut file, 1, false, input, out, false) == 0
	service_file_work()
	assert manager.published.len == 0 && !syncobj.is_signaled(fence(out))
	syncobj.signal(generic)
	service_file_work()
	assert manager.published_order == [u32(0)]
	assert manager.execute_firmware(0, 0)
	manager.retire_firmware(0)
	service_file_work()
	assert_drained(file)
}

fn check_recreated_queue_keeps_old_wait() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	a, b := output(), output()
	assert submit(mut file, 1, false, unsafe { nil }, a, false) == 0
	old_context := file.g13_queues[0].resources.fence_context
	// Reuse the public handle with a new physical queue and a new scalar token.
	fresh := &gpu.G13QueueResources{ id: 1, fence_context: syncobj.new_queue_context() or { panic('replacement queue') } }
	assert fresh.fence_context != old_context
	file.g13_queues = [Ownership{ queue_id: 1, resources: fresh }, file.g13_queues[1]]
	assert submit(mut file, 1, false, a, b, false) == 0
	service_file_work()
	assert manager.published_order == [u32(0)]
	assert manager.execute_firmware(0, 0)
	manager.retire_firmware(0)
	service_file_work()
	assert manager.published_order == [u32(0), 1]
	assert manager.execute_firmware(1, 0)
	manager.retire_firmware(1)
	service_file_work()
	assert_drained(file)
}
