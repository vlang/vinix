module gpu

import gpu.agx.event
import gpu.agx.mmu

fn initial_job(mut mgr GpuManager, mut queue G13QueueResources, context &mmu.UatContext,
	completion &Completion, render bool) G13SubmissionJob {
	if render { return G13SubmissionJob{ render: mgr.render_job(mut queue, context, completion) } }
	return G13SubmissionJob{ compute: mgr.compute_job(mut queue, context, completion) }
}

fn initial_accept(mut mgr GpuManager, source G13SubmissionJob) {
	mut jobs := [64]G13SubmissionJob{}
	jobs[0] = source
	mgr.lock.acquire()
	assert mgr.accept_g13_submission_locked(jobs, 1)
	mgr.lock.release()
}

fn initial_publish(source G13SubmissionJob) {
	if source.compute != unsafe { nil } {
		mut job := unsafe { source.compute }
		mut queue := unsafe { job.queue }
		assert queue.subqueues[2].events.publish(job.event_slot, job.stamp_value)
		job.submitted = true
		job.retirement_sequence = 1
	} else {
		mut job := unsafe { source.render }
		mut queue := unsafe { job.queue }
		assert queue.subqueues[0].events.publish(job.vertex_event_slot, job.vertex_stamp_value)
		assert queue.subqueues[1].events.publish(job.fragment_event_slot, job.fragment_stamp_value)
		job.submitted = true
		job.vertex_retirement_sequence = 1
		job.fragment_retirement_sequence = 1
	}
}

fn initial_retire(mut mgr GpuManager, source G13SubmissionJob, mut driver [128]u32) {
	if source.compute != unsafe { nil } {
		driver[source.compute.event_slot] = source.compute.stamp_value
		mgr.reap_g13_compute_jobs()
	} else {
		driver[source.render.vertex_event_slot] = source.render.vertex_stamp_value
		driver[source.render.fragment_event_slot] = source.render.fragment_stamp_value
		mgr.reap_g13_render_jobs()
	}
}

fn initial_discard(mut mgr GpuManager, source G13SubmissionJob) {
	if source.compute != unsafe { nil } {
		mgr.release_g13_compute_job(source.compute)
	} else {
		mgr.release_g13_render_job(source.render)
	}
}

fn check_initial_barrier_lifetimes() {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	for render_consumer in [false, true]! {
		for mode in 0 .. 7 {
			for _ in 0 .. 10 {
				mut mgr := GpuManager{}
				mut queue := G13QueueResources{}
				mut context := mmu.UatContext{}
				mut producer_done := Completion{}
				mut consumer_done := Completion{}
				producer := initial_job(mut mgr, mut queue, &context, &producer_done, !render_consumer)
				initial_accept(mut mgr, producer)
				pipe := if render_consumer { 1 } else { 0 }
				capture := mgr.capture_g13_initial_events(&queue, u32(1) << pipe) or { panic('capture') }
				assert capture.values[pipe].valid && !capture.values[1 - pipe].valid
				wait := capture.values[pipe].ticket
				consumer := initial_job(mut mgr, mut queue, &context, &consumer_done, render_consumer)
				mut bytes := [4096]u8{init: 0xa5}
				owner := SharedBuffer{ phys: unsafe { u64(&bytes) }, va: 0x100000, size: sizeof(bytes) }
				mut sources := [2]G13BarrierSource{}
				sources[pipe] = G13BarrierSource{ initial: capture.values[pipe] }
				mut barriers := &G13CommandBarriers(unsafe { nil })
				mut buffer := &SharedBuffer(unsafe { nil })
				mut self_value := u32(0)
				if render_consumer {
					unsafe {
						consumer.render.init_buffer = owner
						consumer.render.explicit_barriers.offset = 0x80
					}
					assert mgr.set_g13_render_barriers(consumer.render, sources)
					barriers, buffer, self_value = unsafe { &consumer.render.explicit_barriers }, unsafe { &consumer.render.init_buffer }, consumer.render.vertex_stamp_value
				} else {
					unsafe {
						consumer.compute.microsequence = owner
						consumer.compute.explicit_barriers.offset = 0x80
					}
					assert mgr.set_g13_compute_barriers(consumer.compute, sources)
					barriers, buffer, self_value = unsafe { &consumer.compute.explicit_barriers }, unsafe { &consumer.compute.microsequence }, consumer.compute.stamp_value
				}
				mgr.release_g13_initial_events(capture)
				assert barriers.pin_count == 1 && !barriers.publishable(&owner)
				canceled := mode == 2 || mode == 4 || mode == 6
				if mode == 0 {
					assert !mgr.resolve_g13_initial_barriers_locked(mut barriers, mut buffer, &queue, self_value)
				}
				if canceled {
					initial_discard(mut mgr, producer)
				} else {
					initial_publish(producer)
				}
				if mode == 3 { initial_retire(mut mgr, producer, mut driver) }
				mgr.flush_fails = mode == 4 || mode == 5
				assert mgr.resolve_g13_initial_barriers_locked(mut barriers, mut buffer, &queue, self_value), 'initial barriers must resolve when firmware flushes are refused'
				assert mgr.flushes == 0
				assert barriers.count == if canceled { 0 } else { 1 }
				assert barriers.pin_count == 1 && barriers.publishable(&owner)
				if !canceled { expect_barrier(&bytes, 0x80, wait.slot, wait.value, self_value) }
				if !canceled && mode != 3 { initial_retire(mut mgr, producer, mut driver) }
				expect_free_events(if render_consumer { 125 } else { 126 }, int(wait.slot))
				mgr.invalidation_fails = mode == 6
				initial_discard(mut mgr, consumer)
				if mode == 6 {
					expect_free_events(if render_consumer { 125 } else { 126 }, int(wait.slot))
					mgr.invalidation_fails = false
					if render_consumer {
						mgr.reap_g13_render_jobs()
					} else {
						mgr.reap_g13_compute_jobs()
					}
				}
				assert producer_done.calls == 1 && consumer_done.calls == 1
				expect_free_events(128, -1)
			}
		}
	}
	event.reset_event_manager()
	println('AGX initial prefixes: 140 acceptance, cancellation, resolution, firmware flush refusal and retirement cycles return all 128 slots')
}

fn check_initial_cancellation_fallback() {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	mut mgr := GpuManager{}
	mut queue := G13QueueResources{}
	mut context := mmu.UatContext{}
	mut completions := [4]Completion{}
	older := initial_job(mut mgr, mut queue, &context, unsafe { &completions[0] }, false)
	initial_accept(mut mgr, older)
	target := initial_job(mut mgr, mut queue, &context, unsafe { &completions[1] }, false)
	initial_accept(mut mgr, target)
	capture := mgr.capture_g13_initial_events(&queue, 2) or { panic('capture') }
	wait := capture.values[1].ticket
	consumer := initial_job(mut mgr, mut queue, &context, unsafe { &completions[2] }, true)
	mut bytes := [4096]u8{}
	unsafe {
		consumer.render.init_buffer = SharedBuffer{ phys: u64(&bytes), va: 0x100000, size: sizeof(bytes) }
		consumer.render.explicit_barriers.offset = 0x80
	}
	mut sources := [2]G13BarrierSource{}
	sources[1] = G13BarrierSource{ initial: capture.values[1] }
	assert mgr.set_g13_render_barriers(consumer.render, sources)
	mgr.release_g13_initial_events(capture)
	initial_discard(mut mgr, target)
	future := initial_job(mut mgr, mut queue, &context, unsafe { &completions[3] }, false)
	future_ticket := queue.subqueues[2].events.ticket(future.compute.event_slot, future.compute.stamp_value) or { panic('future') }
	assert future_ticket.value == wait.value && future_ticket.sequence == wait.sequence && future_ticket.serial != wait.serial
	mut job := unsafe { consumer.render }
	assert !mgr.resolve_g13_initial_barriers_locked(mut job.explicit_barriers, mut job.init_buffer, &queue, job.vertex_stamp_value)
	initial_publish(older)
	assert mgr.resolve_g13_initial_barriers_locked(mut job.explicit_barriers, mut job.init_buffer, &queue, job.vertex_stamp_value)
	expect_barrier(&bytes, 0x80, older.compute.event_slot, older.compute.stamp_value, job.vertex_stamp_value)
	initial_retire(mut mgr, older, mut driver)
	initial_discard(mut mgr, future)
	initial_discard(mut mgr, consumer)
	assert completions.all(it.calls == 1)
	expect_free_events(128, -1)
	event.reset_event_manager()
	println('AGX initial wire: canceled target falls back to older published work, excludes future ABA reservation, retains pins through cleanup')
}

fn check_initial_acceptance_and_reset() {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	mut mgr := GpuManager{}
	mut queue := G13QueueResources{}
	mut context := mmu.UatContext{}
	mut completions := [3]Completion{}
	a := initial_job(mut mgr, mut queue, &context, unsafe { &completions[0] }, false)
	initial_accept(mut mgr, a)
	marker := queue.initial_events[1].ticket.serial
	b := initial_job(mut mgr, mut queue, &context, unsafe { &completions[1] }, false)
	// Equal queue contents still represent distinct ownership identities.
	mut foreign := queue
	mut second := unsafe { b.compute }
	second.queue = unsafe { &foreign }
	mut mixed := [64]G13SubmissionJob{}
	mixed[0], mixed[1] = a, b
	assert !mgr.accept_g13_submission_locked(mixed, 2)
	second.queue = unsafe { &queue }
	render := initial_job(mut mgr, mut queue, &context, unsafe { &completions[2] }, true)
	mut jobs := [64]G13SubmissionJob{}
	jobs[0], jobs[1] = b, render
	mut invalid := unsafe { render.render }
	original := invalid.vertex_stamp_value
	invalid.vertex_stamp_value += 0x100
	assert !mgr.accept_g13_submission_locked(jobs, 2)
	assert queue.initial_events[1].ticket.serial == marker && !queue.initial_events[0].valid
	invalid.vertex_stamp_value = original
	initial_accept(mut mgr, render)
	slot := a.compute.event_slot
	assert event.test_force_refs(slot, ~u32(0)) == 1
	assert mgr.capture_g13_initial_events(&queue, 3) == none
	// Roll back the successful first pin, but do not touch an unused overflowed pipe.
	fragment_slot := render.render.fragment_event_slot
	assert event.test_force_refs(fragment_slot, 1) == 1
	only_render := mgr.capture_g13_initial_events(&queue, 1) or { panic('unused overflow must not block') }
	mgr.release_g13_initial_events(only_render)
	assert event.test_force_refs(slot, 1) == ~u32(0)
	capture := mgr.capture_g13_initial_events(&queue, 2) or { panic('capture before reset') }
	initial_discard(mut mgr, render)
	initial_discard(mut mgr, b)
	initial_discard(mut mgr, a)
	expect_free_events(127, int(slot))
	event.reset_event_manager()
	mgr.state = .stopped
	mgr.g13_events.initialized = false
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	fresh := event.reserve_stamp() or { panic('new manager owner') }
	mgr.release_g13_initial_events(capture)
	expect_free_events(127, int(fresh))
	event.release_stamp(fresh)
	event.reset_event_manager()
	println('AGX initial admission: invalid vertex rejects atomic acceptance, partial capture overflow rolls back, unused pipes do not pin, old reset releases never touch a new manager')
}

fn check_initial_compaction() {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	mut mgr := GpuManager{}
	mut queue := G13QueueResources{}
	mut context := mmu.UatContext{}
	mut completions := [4]Completion{}
	render := initial_job(mut mgr, mut queue, &context, unsafe { &completions[0] }, true)
	compute := initial_job(mut mgr, mut queue, &context, unsafe { &completions[1] }, false)
	initial_accept(mut mgr, render)
	initial_accept(mut mgr, compute)
	capture := mgr.capture_g13_initial_events(&queue, 3) or { panic('two sources') }
	mut bytes := [4096]u8{}
	owner := SharedBuffer{ phys: unsafe { u64(&bytes) }, va: 0x100000, size: sizeof(bytes) }
	bad := initial_job(mut mgr, mut queue, &context, unsafe { &completions[3] }, false)
	unsafe {
		bad.compute.microsequence = owner
		bad.compute.explicit_barriers.offset = 0x80
	}
	mut wrong := [2]G13BarrierSource{}
	wrong[1] = G13BarrierSource{ initial: capture.values[0] }
	assert !mgr.set_g13_compute_barriers(bad.compute, wrong)
	assert bad.compute.explicit_barriers.pin_count == 0
	initial_discard(mut mgr, bad)
	consumer := initial_job(mut mgr, mut queue, &context, unsafe { &completions[2] }, true)
	unsafe {
		consumer.render.init_buffer = owner
		consumer.render.explicit_barriers.offset = 0x80
	}
	mut sources := [2]G13BarrierSource{}
	for pipe in 0 .. 2 { sources[pipe] = G13BarrierSource{ initial: capture.values[pipe] } }
	assert mgr.set_g13_render_barriers(consumer.render, sources)
	mgr.release_g13_initial_events(capture)
	initial_discard(mut mgr, render)
	mut job := unsafe { consumer.render }
	assert !mgr.resolve_g13_initial_barriers_locked(mut job.explicit_barriers, mut job.init_buffer, &queue, job.vertex_stamp_value)
	assert job.explicit_barriers.count == 2 && job.explicit_barriers.pin_count == 2
	initial_publish(compute)
	mgr.flush_fails = true
	before := bytes
	job.init_buffer.va = 0
	assert !mgr.resolve_g13_initial_barriers_locked(mut job.explicit_barriers, mut job.init_buffer, &queue, job.vertex_stamp_value)
	assert bytes == before && job.explicit_barriers.initial_pending && job.explicit_barriers.pin_count == 2
	job.init_buffer.va = owner.va
	assert mgr.resolve_g13_initial_barriers_locked(mut job.explicit_barriers, mut job.init_buffer, &queue, job.vertex_stamp_value)
	assert mgr.flushes == 0
	assert job.explicit_barriers.count == 1 && job.explicit_barriers.pin_count == 2
	expect_barrier(&bytes, 0x80, compute.compute.event_slot, compute.compute.stamp_value, job.vertex_stamp_value)
	initial_retire(mut mgr, compute, mut driver)
	mgr.invalidation_fails = true
	initial_discard(mut mgr, consumer)
	expect_free_events(125, -1)
	mgr.invalidation_fails = false
	mgr.reap_g13_render_jobs()
	assert completions.all(it.calls == 1)
	expect_free_events(128, -1)
	event.reset_event_manager()
	println('AGX initial compaction: reject wrong pipe, wait for second source, compact two records to one and retain both pins through quarantine')
}
