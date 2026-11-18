module gpu

import gpu.agx.event
import gpu.agx.fw
import gpu.agx.mmu

fn check_batch_admission() {
	check_batch_event_window()
	check_mixed_event_windows()
	check_batch_ring_window()
	check_batch_initial_resolution()
	check_batch_cancellation_grant()
	println('AGX batch admission: actual production preflight, all-pipe strict event/ring boundaries, host-retirement retry, TVB bind/growth simulation, identity/ownership and initial-prefix flush retry pass')
}

fn check_batch_cancellation_grant() {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	for render in [false, true]! {
		mut mgr := GpuManager{}
		mut queue := G13QueueResources{}
		mut context := mmu.UatContext{}
		mut completions := [127]Completion{}
		mut canceled := [125]G13SubmissionJob{}
		for index in 0 .. 125 { canceled[index] = initial_job(mut mgr, mut queue, &context, unsafe { &completions[index] }, render) }
		mut jobs := [64]G13SubmissionJob{}
		for index in 0 .. 2 { jobs[index] = initial_job(mut mgr, mut queue, &context, unsafe { &completions[index + 125] }, render) }
		for index := 124; index >= 0; index-- { initial_discard(mut mgr, canceled[index]) }
		assert mgr.g13_batch_ready(jobs, 2)
		initial_publish(jobs[0])
		initial_publish(jobs[1]) // must not charge the already admitted event again
		initial_retire(mut mgr, jobs[1], mut driver)
		assert completions.all(it.calls == 1)
		// Retain/reuse clears the grant; ordinary single-command publication
		// still enforces the spare and cannot inherit stale batch authority.
		mut events := event.WorkQueueEvents{}
		mut tickets := [127]event.Ticket{}
		for index in 0 .. 127 { tickets[index] = events.retain() or { panic('grant reuse') } }
		for index in 0 .. 126 { assert events.publish(tickets[index].slot, tickets[index].value) }
		assert !events.publish(tickets[126].slot, tickets[126].value)
		assert events.admit(tickets[126].slot, tickets[126].value)
		assert events.can_publish(tickets[126].slot, tickets[126].value)
		assert events.release(tickets[126].slot, tickets[126].value, false)
		reused := events.retain() or { panic('canceled grant reuse') }
		assert !events.publish(reused.slot, reused.value), 'a reused ticket cannot inherit canceled admission'
		assert events.release(reused.slot, reused.value, false)
		for index := 125; index >= 0; index-- { assert events.release(tickets[index].slot, tickets[index].value, true) }
		expect_free_events(128, -1)
	}
	event.reset_event_manager()
}

fn check_mixed_event_windows() {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	for pipe in 0 .. 3 {
		mut mgr := GpuManager{}
		mut queue := G13QueueResources{}
		mut context := mmu.UatContext{}
		mut older := [126]event.Ticket{}
		for index in 0 .. 126 {
			older[index] = queue.subqueues[pipe].events.retain() or { panic('older event') }
			assert queue.subqueues[pipe].events.publish(older[index].slot, older[index].value)
		}
		mut completions := [2]Completion{}
		mut jobs := [64]G13SubmissionJob{}
		jobs[0] = initial_job(mut mgr, mut queue, &context, unsafe { &completions[0] }, false)
		jobs[1] = initial_job(mut mgr, mut queue, &context, unsafe { &completions[1] }, true)
		assert !mgr.g13_batch_ready(jobs, 2), 'each physical pipe independently holds the entire mixed batch'
		assert !jobs[0].compute.submitted && !jobs[1].render.submitted
		assert queue.subqueues[pipe].events.release(older[0].slot, older[0].value, true)
		assert mgr.g13_batch_ready(jobs, 2)
		initial_discard(mut mgr, jobs[1])
		initial_discard(mut mgr, jobs[0])
		for index in 1 .. 126 { assert queue.subqueues[pipe].events.release(older[index].slot, older[index].value, true) }
		assert completions.all(it.calls == 1)
		expect_free_events(128, -1)
	}
	event.reset_event_manager()
}

fn check_batch_event_window() {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	for render in [false, true]! {
		mut mgr := GpuManager{}
		mut queue := G13QueueResources{}
		mut context := mmu.UatContext{}
		mut completions := [128]Completion{}
		mut older := [63]G13SubmissionJob{}
		mut batch := [64]G13SubmissionJob{}
		for index in 0 .. 63 {
			older[index] = initial_job(mut mgr, mut queue, &context, unsafe { &completions[index] }, render)
			initial_publish(older[index])
		}
		for index in 0 .. 64 {
			batch[index] = initial_job(mut mgr, mut queue, &context, unsafe { &completions[index + 63] }, render)
		}
		assert !mgr.g13_batch_ready(batch, 64), 'free64 must refuse batch64 before its first publication'
		assert if render { !batch[0].render.submitted } else { !batch[0].compute.submitted }
		// Raw GPU progress cannot grant host capacity before the actual reaper.
		if render { driver[older[0].render.fragment_event_slot] = older[0].render.fragment_stamp_value }
		else { driver[older[0].compute.event_slot] = older[0].compute.stamp_value }
		assert !mgr.g13_batch_ready(batch, 64)
		initial_retire(mut mgr, older[0], mut driver)
		assert mgr.g13_batch_ready(batch, 64), 'one real host retirement admits the whole batch'
		for index := 63; index >= 0; index-- { initial_discard(mut mgr, batch[index]) }
		for index in 1 .. 63 { initial_retire(mut mgr, older[index], mut driver) }
		assert completions[..127].all(it.calls == 1)
		expect_free_events(128, -1)
	}
	event.reset_event_manager()
}

fn check_batch_ring_window() {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	mut mgr := GpuManager{}
	mut queue := G13QueueResources{}
	mut context := mmu.UatContext{}
	mut completions := [4]Completion{}
	mut jobs := [64]G13SubmissionJob{}
	for index in 0 .. 4 { jobs[index] = initial_job(mut mgr, mut queue, &context, unsafe { &completions[index] }, index != 1) }
	// Vertex: initial bind+run, then grow+run, then run =5, with 0/1/2
	// explicit prefixes on these renders =8. Fragment=6; compute=3.
	queue.render_buffer.needs_bind = true
	unsafe {
		jobs[0].render.tvb_size_bytes = fw.g13_tvb_block_size
		jobs[2].render.tvb_size_bytes = fw.g13_tvb_block_size * 2
		jobs[3].render.tvb_size_bytes = fw.g13_tvb_block_size * 2
		jobs[2].render.explicit_barriers = G13CommandBarriers{ count: 1, offset: 0x80 }
		jobs[3].render.explicit_barriers = G13CommandBarriers{ count: 2, offset: 0x80 }
		jobs[1].compute.explicit_barriers = G13CommandBarriers{ count: 2, offset: 0x80 }
		jobs[2].render.init_buffer = SharedBuffer{ va: 0x100000, size: 0x1000 }
		jobs[3].render.init_buffer = SharedBuffer{ va: 0x200000, size: 0x1000 }
		jobs[1].compute.microsequence = SharedBuffer{ va: 0x300000, size: 0x1000 }
	}
	assert mgr.g13_batch_ready(jobs, 4)
	assert queue.render_buffer.needs_bind && queue.render_buffer.bound_blocks == 0
	for pipe, count in [u32(8), 6, 3]! {
		queue.subqueues[pipe].command_sequence = u64(fw.g13_workqueue_entries - 1 - count)
		assert !mgr.g13_batch_ready(jobs, 4), 'equality must hold every other pipe before publication'
		queue.subqueues[pipe].retired_sequence = 1
		assert mgr.g13_batch_ready(jobs, 4)
		queue.subqueues[pipe].command_sequence = 0
		queue.subqueues[pipe].retired_sequence = 0
	}
	// A pre-bound TVB removes both InitBuffer entries, leaving vertex6.
	queue.render_buffer.needs_bind = false
	queue.render_buffer.bound_blocks = 2
	queue.subqueues[0].command_sequence = u64(fw.g13_workqueue_entries - 1 - 6)
	assert !mgr.g13_batch_ready(jobs, 4)
	queue.subqueues[0].retired_sequence = 1
	assert mgr.g13_batch_ready(jobs, 4)
	queue.subqueues[0].command_sequence, queue.subqueues[0].retired_sequence = 0, 0
	mut foreign := queue
	unsafe { jobs[3].render.queue = &foreign }
	assert !mgr.g13_batch_ready(jobs, 4), 'equal queue contents cannot replace physical ownership'
	unsafe { jobs[3].render.queue = &queue }
	value := jobs[3].render.vertex_stamp_value
	unsafe { jobs[3].render.vertex_stamp_value += 0x100 }
	assert !mgr.g13_batch_ready(jobs, 4)
	unsafe { jobs[3].render.vertex_stamp_value = value }
	assert !mgr.g13_batch_ready(jobs, 0) && !mgr.g13_batch_ready(jobs, 65)
	queue.quarantined = true
	assert !mgr.g13_batch_ready(jobs, 4)
	queue.quarantined = false
	queue.subqueues[2].retired_sequence = 1
	assert !mgr.g13_batch_ready(jobs, 4) && mgr.state == .error
	mgr.state = .running
	queue.subqueues[2].retired_sequence = 0
	for index := 3; index >= 0; index-- { initial_discard(mut mgr, jobs[index]) }
	assert completions.all(it.calls == 1)
	expect_free_events(128, -1)
	event.reset_event_manager()
}

fn check_batch_initial_resolution() {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	mut mgr := GpuManager{}
	mut queue := G13QueueResources{}
	mut context := mmu.UatContext{}
	mut completions := [2]Completion{}
	producer := initial_job(mut mgr, mut queue, &context, unsafe { &completions[0] }, false)
	initial_accept(mut mgr, producer)
	capture := mgr.capture_g13_initial_events(&queue, 2) or { panic('capture') }
	consumer := initial_job(mut mgr, mut queue, &context, unsafe { &completions[1] }, true)
	mut bytes := [4096]u8{}
	unsafe {
		consumer.render.init_buffer = SharedBuffer{ phys: u64(&bytes), va: 0x100000, size: sizeof(bytes) }
		consumer.render.explicit_barriers.offset = 0x80
	}
	mut sources := [2]G13BarrierSource{}
	sources[1] = G13BarrierSource{ initial: capture.values[1] }
	assert mgr.set_g13_render_barriers(consumer.render, sources)
	mgr.release_g13_initial_events(capture)
	mut batch := [64]G13SubmissionJob{}
	batch[0] = consumer
	assert !mgr.g13_batch_ready(batch, 1), 'an unpublished initial source cannot pass preflight'
	initial_discard(mut mgr, producer)
	mgr.flush_fails = true
	assert !mgr.g13_batch_ready(batch, 1)
	assert consumer.render.explicit_barriers.initial_pending && consumer.render.explicit_barriers.pin_count == 1
	mgr.flush_fails = false
	// After compaction, vertex needs one record rather than two; free2 admits.
	queue.render_buffer.needs_bind = false
	queue.subqueues[0].command_sequence = fw.g13_workqueue_entries - 3
	assert mgr.g13_batch_ready(batch, 1)
	assert consumer.render.explicit_barriers.count == 0 && !consumer.render.explicit_barriers.initial_pending
	assert consumer.render.explicit_barriers.pin_count == 1 && !consumer.render.submitted
	initial_discard(mut mgr, consumer)
	assert completions.all(it.calls == 1)
	expect_free_events(128, -1)
	event.reset_event_manager()
}
