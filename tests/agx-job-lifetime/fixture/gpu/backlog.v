module gpu

import gpu.agx.alloc
import gpu.agx.channel
import gpu.agx.event
import gpu.agx.fw
import gpu.agx.mmu
import memory

fn check_prepared_job_backlog() {
	for render in [false, true]! {
		for stop in [false, true]! { check_queued_job_backlog(render, stop) }
	}
	check_partial_render_backlog_failure()
	println('AGX prepared backlog: 512 real compute/render jobs, eight native64-command batches, host-capacity waits, block-spanning captures, failed invalidation/quarantine retry, stopped caller ownership and partial render OOM return every overflow block and physical event')
}

fn check_queued_job_backlog(render bool, stop bool) {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	mut present := u8(1)
	mut mgr := GpuManager{ g13_channels: &present, expected_owned: 64 }
	mut queue := G13QueueResources{}
	mut context := mmu.UatContext{}
	mut jobs := [512]G13SubmissionJob{}
	mut completions := [512]Completion{}
	mut threshold := u64(0)
	mut counter := u32(0)
	mut headers := [3]channel.RingHeader{}
	mut states := [3]fw.G13WorkQueueRingState{}
	mut rings := [3][1280]u64{}
	mut messages := [3][16]fw.FwRunWorkQueueMsg{}
	queue.threshold = SharedBuffer{ phys: unsafe { u64(&threshold) }, size: sizeof(threshold) }
	queue.render_buffer.counter = SharedBuffer{ phys: unsafe { u64(&counter) }, size: sizeof(counter) }
	for pipe in 0 .. 3 {
		mgr.channels.pipes[pipe] = channel.new_tx_channel('backlog', 1, unsafe { u64(&headers[pipe]) }, 1,
			unsafe { u64(&messages[pipe]) }, 16, u32(sizeof(fw.FwRunWorkQueueMsg)))
		queue.subqueues[pipe].state = SharedBuffer{ phys: unsafe { u64(&states[pipe]) }, size: sizeof(fw.G13WorkQueueRingState) }
		queue.subqueues[pipe].ring = SharedBuffer{ phys: unsafe { u64(&rings[pipe]) }, size: 1280 * sizeof(u64) }
		queue.subqueues[pipe].info.va = 0x100000 + u64(pipe) * 0x10000
		queue.subqueues[pipe].is_new = true
	}
	for index in 0 .. 512 {
		jobs[index] = initial_job(mut mgr, mut queue, &context, unsafe { &completions[index] }, render)
		base := alloc.g13_gpu_readonly_start + u64(index) * 0x10000
		if render {
			unsafe {
				jobs[index].render.vertex.va = base
				jobs[index].render.fragment.va = base + 0x1000
				jobs[index].render.barrier.va = base + 0x2000
				jobs[index].render.init_buffer.va = base + 0x4000
			}
		} else { unsafe { jobs[index].compute.command.va = base } }
		initial_accept(mut mgr, jobs[index])
	}
	assert memory.outstanding() == if render { 8 } else { 4 }
	mask := if render { u32(1) } else { u32(2) }
	logical := if render { 0 } else { 1 }
	physical := if render { 1 } else { 2 }
	capture := mgr.capture_g13_initial_events(&queue, mask) or { panic('backlog capture') }
	target := capture.values[logical].ticket
	for start := 0; start < 512; start += 64 {
		mut batch := [64]G13SubmissionJob{}
		for offset in 0 .. 64 { batch[offset] = jobs[start + offset] }
		assert mgr.submit_g13_batch(batch, 64, false) == ~u64(0)
		assert mgr.pending == 1
		state, resolved := queue.subqueues[physical].events.resolve_initial(target)
		assert state == if start == 448 { event.InitialState.ready } else { event.InitialState.pending }
		if start == 448 { assert resolved.serial == target.serial }
		if start < 448 {
			mut later := [64]G13SubmissionJob{}
			for offset in 0 .. 64 { later[offset] = jobs[start + 64 + offset] }
			assert mgr.submit_g13_batch(later, 64, false) == 0, 'queued reservations do not increase hardware credit'
		}
		if stop {
			mgr.pending = 0 // Firmware globals are released on stop.
			mgr.state = .stopped
			mgr.release_all_g13_compute_jobs()
			mgr.release_all_g13_render_jobs()
			for index := 511; index >= 64; index-- { initial_discard(mut mgr, jobs[index]) }
			break
		}
		for offset in 0 .. 64 {
			source := jobs[start + offset]
			if render { driver[source.render.vertex_event_slot] = source.render.vertex_stamp_value; driver[source.render.fragment_event_slot] = source.render.fragment_stamp_value }
			else { driver[source.compute.event_slot] = source.compute.stamp_value }
		}
		for pipe in 0 .. 3 {
			states[pipe].gpu_doneptr = states[pipe].cpu_wptr
			headers[pipe].read_ptr = headers[pipe].write_ptr
		}
		if start == 128 { mgr.invalidation_fails = true }
		if render { mgr.reap_g13_render_jobs() } else { mgr.reap_g13_compute_jobs() }
		if start == 128 {
			assert mgr.g13_queue_dispatch_blocked_locked(&queue)
			kept := memory.outstanding()
			mgr.invalidation_fails = false
			if render { mgr.reap_g13_render_jobs() } else { mgr.reap_g13_compute_jobs() }
			assert !mgr.g13_queue_dispatch_blocked_locked(&queue) && memory.outstanding() <= kept
		}
		assert mgr.pending == 1
		mgr.finish_g13_submission_operation()
		assert mgr.pending == 0
	}
	assert completions.all(it.calls == 1) && memory.outstanding() == 0
	assert mgr.g13_compute_jobs.len == 0 && mgr.g13_render_jobs.len == 0 && mgr.pending == 0
	expect_free_events(127, int(target.slot))
	mgr.release_g13_initial_events(capture)
	expect_free_events(128, -1)
	event.reset_event_manager()
}

fn check_partial_render_backlog_failure() {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	mut mgr := GpuManager{}
	mut queue := G13QueueResources{}
	mut context := mmu.UatContext{}
	mut completions := [127]Completion{}
	mut jobs := [127]G13SubmissionJob{}
	for index in 0 .. 127 { jobs[index] = initial_job(mut mgr, mut queue, &context, unsafe { &completions[index] }, true) }
	mut victim := &G13RenderJobResources{ queue: &queue, context: &context }
	memory.fail_after(1)
	vertex := queue.subqueues[0].events.retain() or { panic('first overflow must allocate') }
	victim.vertex_event_slot, victim.vertex_stamp_value, victim.vertex_event_reserved = vertex.slot, vertex.value, true
	assert queue.subqueues[1].events.retain() == none && memory.outstanding() == 1
	mgr.release_g13_render_job(victim)
	memory.fail_after(-1)
	assert mgr.g13_render_jobs.len == 127 && memory.outstanding() == 0
	for index := 126; index >= 0; index-- { initial_discard(mut mgr, jobs[index]) }
	assert completions.all(it.calls == 1) && memory.outstanding() == 0
	expect_free_events(128, -1)
	event.reset_event_manager()
}
