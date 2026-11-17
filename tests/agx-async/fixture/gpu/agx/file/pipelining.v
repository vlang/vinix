@[has_globals]
module file

import drm.gem
import drm.ioctl
import drm.syncobj
import gpu.agx.gpu
import memory

fn check_later_submission_completes_first() {
	for render_first in [false, true]! {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		mut results := [128]u8{}
		mut object := gem.GemObject{ size: sizeof(results), virt_addr: unsafe { u64(&results) } }
		file.objects = Objects{ object: &object }
		a, b := output(), output()
		assert submit_scheduled(mut file, [ScheduledCommand{ compute: !render_first }], a, true) == 0
		assert submit_scheduled(mut file, [ScheduledCommand{ compute: render_first }], b, true) == 0
		service_file_work()
		assert manager.published_order == [u32(0), 1] && pending_count == 2
		assert file.inflight_by_vm[1] == 4 && object.references == 3
		assert manager.execute_firmware(1, 0), 'independent later submission may execute first'
		manager.retire_firmware(1)
		service_file_work()
		assert syncobj.is_signaled(fence(b)) && !syncobj.is_signaled(fence(a))
		assert pending_count == 1 && memory.outstanding() == 1
		assert file.inflight_by_vm[1] == 2 && object.references == 2
		assert manager.execute_firmware(0, 0)
		manager.retire_firmware(0)
		service_file_work()
		assert syncobj.is_signaled(fence(a)) && object.references == 1
		assert_drained(file)
	}
}

fn check_initial_dependencies_hold_followers() {
	for pipe in 0 .. 2 {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		a, b, c, independent := output(), output(), output(), output()
		assert submit_scheduled(mut file, [ScheduledCommand{ compute: pipe == 1 }], a, false) == 0
		initial := ScheduledCommand{
			compute:         pipe == 0
			render_barrier:  if pipe == 0 { 0 } else { ioctl.asahi_barrier_none }
			compute_barrier: if pipe == 1 { 0 } else { ioctl.asahi_barrier_none }
		}
		assert submit_scheduled(mut file, [initial], b, false) == 0
		assert pending_tail.initial_barriers == u32(1) << pipe
		assert submit_scheduled(mut file, [ScheduledCommand{ compute: pipe == 1 }], c, false) == 0
		assert submit_scheduled_on_queue(mut file, 2, [ScheduledCommand{ compute: true }], independent, false) == 0
		// A client-signaled user fence cannot release an internal dependency.
		syncobj.signal(fence(a))
		service_file_work()
		assert manager.published_order == [u32(0), 1, 2, 3]
		assert !manager.execute_firmware(1, 0), 'the initial prefix still waits for the producer in firmware'
		service_file_work()
		assert manager.published_order == [u32(0), 1, 2, 3]
		assert manager.execute_firmware(3, 0)
		manager.retire_firmware(3)
		assert manager.execute_firmware(0, 0)
		manager.retire_firmware(0)
		service_file_work()
		assert manager.published_order == [u32(0), 1, 2, 3]
		for index := u32(1); index < 3; index++ {
			assert manager.execute_firmware(index, 0)
			manager.retire_firmware(index)
		}
		service_file_work()
		assert syncobj.is_signaled(fence(b)) && syncobj.is_signaled(fence(c))
		assert_drained(file)
	}
}

fn check_partial_publication_holds_followers() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	a, b, c := output(), output(), output()
	assert submit_scheduled(mut file, [ScheduledCommand{ compute: true }, ScheduledCommand{}], a, false) == 0
	assert submit_scheduled(mut file, [ScheduledCommand{ compute: true }], b, false) == 0
	assert submit_scheduled_on_queue(mut file, 2, [ScheduledCommand{ compute: true }], c, false) == 0
	manager.render_ring_full = true
	service_file_work()
	assert manager.published_order == [u32(0), 3]
	manager.render_ring_full = false
	service_file_work()
	assert manager.published_order == [u32(0), 3, 1, 2], 'finish older publication before a newer batch'
	manager.stop()
	service_file_work()
	assert_drained(file)
}

fn check_pipelined_failure_and_stop() {
	for stop in [false, true]! {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		a, b := output(), output()
		assert submit_scheduled(mut file, [ScheduledCommand{ compute: true }], a, false) == 0
		assert submit_scheduled(mut file, [ScheduledCommand{}], b, false) == 0
		service_file_work()
		assert manager.published_order == [u32(0), 1]
		assert manager.execute_firmware(0, 3)
		manager.retire_firmware(0)
		service_file_work()
		assert syncobj.get_error(fence(a)) == -110 && !syncobj.is_signaled(fence(b))
		assert file.inflight_by_vm[1] == 2 && memory.outstanding() == 1
		if stop {
			manager.stop()
		} else {
			assert manager.execute_firmware(1, 0)
			manager.retire_firmware(1)
		}
		service_file_work()
		assert syncobj.get_error(fence(b)) == if stop { -19 } else { 0 }
		assert_drained(file)
	}
}

fn check_full_pipelined_batches() {
	for render_first in [false, true]! {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		a, b := output(), output()
		first := []ScheduledCommand{len: 64, init: ScheduledCommand{ compute: !render_first }}
		second := []ScheduledCommand{len: 63, init: ScheduledCommand{ compute: render_first }}
		assert submit_scheduled(mut file, first, a, false) == 0
		assert submit_scheduled(mut file, second, b, false) == 0
		service_file_work()
		assert manager.published.len == 127 && file.inflight_by_vm[1] == 129
		// Later batch retires first while the original batch retains its node.
		for index := u32(64); index < 127; index++ {
			assert manager.execute_firmware(index, 0)
		}
		for index := 126; index >= 64; index-- { manager.retire_firmware(u32(index)) }
		service_file_work()
		assert syncobj.is_signaled(fence(b)) && !syncobj.is_signaled(fence(a))
		assert pending_count == 1 && file.inflight_by_vm[1] == 65
		for index := u32(0); index < 64; index++ {
			assert manager.execute_firmware(index, 0)
		}
		for index := 63; index >= 0; index-- { manager.retire_firmware(u32(index)) }
		service_file_work()
		assert_drained(file)
	}
}

fn check_pipelined_concurrent_append() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	out := output()
	assert submit_scheduled(mut file, [ScheduledCommand{ compute: true }, ScheduledCommand{}], out, false) == 0
	older := voidptr(pending_head)
	append_file = file
	manager.on_publish = append_during_poll
	manager.render_ring_full = true
	service_file_work()
	assert pending_count == 2 && voidptr(pending_head) == older && pending_head.next != unsafe { nil }
	assert manager.published_order == [u32(0)]
	service_file_work()
	assert manager.published_order == [u32(0)], 'a concurrent append must not pass unpublished older work'
	manager.render_ring_full = false
	service_file_work()
	assert manager.published_order == [u32(0), 1, 2] && pending_count == 2
	manager.stop()
	service_file_work()
	append_file = unsafe { nil }
	assert_drained(file)
}

fn check_independent_queue_progress() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	for id := u32(3); id <= 129; id++ {
		file.queues << LogicalQueue{ id: id }
		file.g13_queues << Ownership{ queue_id: id, resources: &gpu.G13QueueResources{ id: id } }
	}
	input := output()
	delay := syncobj.new_fence(0, 1)
	syncobj.replace_fence(input, delay)
	for id := u32(1); id <= 128; id++ {
		assert submit(mut file, id, false, input, unsafe { nil }, false) == 0
	}
	assert submit(mut file, 129, false, unsafe { nil }, unsafe { nil }, false) == 0
	assert submit(mut file, 1, false, unsafe { nil }, unsafe { nil }, false) == 0
	assert submit(mut file, 129, false, unsafe { nil }, unsafe { nil }, false) == 0
	mut other := new_file()
	other.owner_key = 2
	assert submit(mut other, 1, false, unsafe { nil }, unsafe { nil }, false) == 0
	service_file_work()
	assert manager.published_order == [u32(128), 130, 131], 'unrelated queues must publish while 128 others wait'
	assert pending_count == 132
	service_file_work()
	assert manager.published_order == [u32(128), 130, 131], 'a later batch on the blocked queue must still wait'
	syncobj.signal(delay)
	service_file_work()
	assert manager.published_order.len == 132 && pending_count == 132
	for index := u32(0); index < 128; index++ {
		assert manager.published_order[int(index) + 3] == index
	}
	assert manager.published_order[131] == 129, 'the blocked queue resumes in FIFO order'
	manager.stop()
	service_file_work()
	assert_drained(file)
	assert_drained(other)
	println('AGX queue progress: independent queues dispatch past 128 blocked queues and FIFO resumes after the input signals.')
}

fn check_stop_during_later_submission() {
	for first_compute in [false, true]! {
		for after_publish in [false, true]! {
			for position in 1 .. 4 {
				gpu.reset()
				mut file := new_file()
				mut manager := gpu.get_global_manager() or { panic('manager') }
				a, b, c := output(), output(), output()
				assert submit_scheduled(mut file, [ScheduledCommand{ compute: first_compute }], a, false) == 0
				assert submit_scheduled(mut file, [ScheduledCommand{},
					ScheduledCommand{ compute: true }, ScheduledCommand{}], b, false) == 0
				assert submit_scheduled(mut file, [ScheduledCommand{ compute: true }], c, false) == 0
				manager.stop_publish_at = if after_publish { position } else { -1 }
				manager.stop_submit_at = if after_publish { -1 } else { position }
				service_file_work()
				service_file_work() // older retained nodes receive stop callbacks during the later poll
				assert manager.published.len == position + if after_publish { 1 } else { 0 }
				assert syncobj.get_error(fence(a)) == -19 && syncobj.get_error(fence(b)) == -19
				assert syncobj.get_error(fence(c)) == -19
				assert_drained(file)
			}
		}
	}
}

fn check_failed_input_between_live_submissions() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	a, b, c, input := output(), output(), output(), output()
	failed := syncobj.new_fence(1, 1)
	syncobj.signal_error(failed, -110)
	syncobj.replace_fence(input, failed)
	assert submit(mut file, 1, false, unsafe { nil }, a, false) == 0
	assert submit(mut file, 1, false, input, b, false) == 0
	assert submit_scheduled(mut file, [ScheduledCommand{}], c, false) == 0
	service_file_work()
	assert manager.published_order == [u32(0), 1, 2] && manager.released_order.len == 0
	assert !syncobj.is_signaled(fence(b)) && !syncobj.is_signaled(fence(a))
	assert pending_count == 3 && file.inflight_by_vm[1] == 6
	assert manager.execute_firmware(2, 0)
	manager.retire_firmware(2)
	assert manager.execute_firmware(0, 0)
	manager.retire_firmware(0)
	assert manager.execute_firmware(1, 0)
	manager.retire_firmware(1)
	service_file_work()
	assert syncobj.is_signaled(fence(b)) && syncobj.get_error(fence(b)) == 0
	assert_drained(file)
}

fn check_submission_pipelining() {
	check_later_submission_completes_first()
	check_initial_dependencies_hold_followers()
	check_partial_publication_holds_followers()
	check_pipelined_failure_and_stop()
	check_full_pipelined_batches()
	check_pipelined_concurrent_append()
	check_independent_queue_progress()
	check_stop_during_later_submission()
	check_failed_input_between_live_submissions()
	println('AGX submission pipelining: reverse retirement/VM/result ownership, index-zero/FIFO, partial/concurrent publication, independent queue progress, failed input, 12 multi-batch shutdown interleavings and overlapping 64+63 jobs passed')
}
