module file

import drm.syncobj
import gpu.agx.gpu
import katomic

fn stop_during_admission() {
	mut manager := gpu.get_global_manager() or { panic('manager') }
	manager.stop()
}

fn check_batch_capacity() {
	for render in [false, true]! {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		a, b, c := output(), output(), output()
		assert submit_scheduled(mut file, []ScheduledCommand{len: 63, init: ScheduledCommand{ compute: !render }}, a, false) == 0
		assert submit_scheduled(mut file, []ScheduledCommand{len: 64, init: ScheduledCommand{ compute: !render }}, b, false) == 0
		assert submit_scheduled_on_queue(mut file, 2, [ScheduledCommand{ compute: true }], c, false) == 0
		service_file_work()
		assert manager.published.len == 64 && manager.published_order[63] == 127
		assert !pending_head.next.admitted, 'no prefix of the blocked64-command batch may publish'
		assert manager.execute_firmware(0, 0)
		service_file_work()
		assert manager.published.len == 64, 'GPU execution without host retirement does not grant capacity'
		manager.retire_firmware(0)
		service_file_work()
		assert manager.published.len == 128 && pending_head.next.admitted
		assert !syncobj.is_signaled(fence(b))
		manager.stop()
		service_file_work()
		assert_drained(file)
		syncobj.destroy_owner(file.owner_key)
	}
	// One full pipe holds a mixed batch's other pipe, and later work on that
	// queue remains FIFO while an unrelated queue proceeds.
	for pipe in 0 .. 3 {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		queue := file.g13_queues[0].resources
		unsafe { queue.admission_space[pipe] = if pipe == 1 { 2 } else { 1 } }
		assert submit_scheduled(mut file, [ScheduledCommand{ compute: true }, ScheduledCommand{}], output(), false) == 0
		assert submit_scheduled(mut file, [ScheduledCommand{ compute: true }], output(), false) == 0
		assert submit_scheduled_on_queue(mut file, 2, [ScheduledCommand{ compute: true }], output(), false) == 0
		service_file_work()
		assert manager.published_order == [u32(3)] && !pending_head.admitted
		unsafe { queue.admission_space[pipe]++ }
		manager.render_ring_full = true // separate outer/publication retry
		service_file_work()
		assert manager.published_order == [u32(3), 0] && pending_head.admitted
		calls := manager.admissions
		service_file_work()
		assert manager.admissions == calls, 'cached admission must never revisit transferred pointers'
		manager.render_ring_full = false
		service_file_work()
		assert manager.published_order == [u32(3), 0, 1, 2]
		manager.stop()
		service_file_work()
		assert_drained(file)
		syncobj.destroy_owner(file.owner_key)
	}
	for pipe in 0 .. 3 {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		queue := file.g13_queues[0].resources
		unsafe { queue.admission_space[pipe] = 0 }
		out := output()
		assert submit_scheduled(mut file, [ScheduledCommand{ compute: true }, ScheduledCommand{}], out, false) == 0
		stop_at_count = pending_head
		katomic.set_load_hook(stop_before_count_load)
		service_file_work()
		katomic.set_load_hook(unsafe { nil })
		stop_at_count = unsafe { nil }
		assert manager.published.len == 0 && manager.released_order.len == 2
		assert syncobj.get_error(fence(out)) == -19
		assert_drained(file)
		syncobj.destroy_owner(file.owner_key)
	}
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	out := output()
	assert submit_scheduled(mut file, [ScheduledCommand{ compute: true }, ScheduledCommand{}], out, false) == 0
	manager.on_admit = stop_during_admission
	service_file_work()
	assert manager.published.len == 0 && syncobj.get_error(fence(out)) == -19
	assert_drained(file)
	syncobj.destroy_owner(file.owner_key)
	println('AGX async admission: 63+64 same-pipe batches wait intact for host retirement, all-pipe mixed capacity/FIFO/independent queues, cached partial publication and stop during readiness pass')
}
