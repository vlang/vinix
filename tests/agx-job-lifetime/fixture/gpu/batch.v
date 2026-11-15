module gpu

import gpu.agx.alloc
import gpu.agx.channel
import gpu.agx.event
import gpu.agx.fw
import gpu.agx.mmu

fn check_batch_publication() {
	for shape in 0 .. 3 {
		for failure in 0 .. 22 { check_batch_transaction(shape, failure, 64) }
		for count in [1, 2, 63]! { check_batch_transaction(shape, 0, count) }
	}
	println('AGX batch publication: 75 actual transactions of 1/2/63/64 jobs, wrapped rings/stamps, canceled gaps, one notification per pipe, every late preparation refusal, missing-middle FIFO, retry, pending rollback, TVB/prefix oracle, counter wrap, notification failure ownership and actual reapers pass')
}

fn check_batch_transaction(shape int, failure int, job_count int) {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	if failure == 20 || failure == 21 { for index in 0 .. 128 { driver[index] = if failure == 20 { u32(0x7fffff00) } else { u32(0xffffff00) } } }
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	mut present := u8(1)
	mut mgr := GpuManager{ g13_channels: &present, batch_pending: 7 }
	mut queue := G13QueueResources{}
	mut context := mmu.UatContext{}
	mut completions := [64]Completion{}
	mut jobs := [64]G13SubmissionJob{}
	mut canceled := [95]G13SubmissionJob{}
	mut canceled_done := [95]Completion{}
	canceled_count := if failure == 19 { if shape == 2 { 95 } else { 63 } } else { 0 }
	for index in 0 .. canceled_count { canceled[index] = initial_job(mut mgr, mut queue, &context, unsafe { &canceled_done[index] }, shape == 1) }
	mut headers := [3]channel.RingHeader{}
	mut states := [3]fw.G13WorkQueueRingState{}
	mut rings := [3][1280]u64{}
	mut messages := [3][4]fw.FwRunWorkQueueMsg{}
	mut threshold := if failure == 16 { ~u64(0) - 31 } else { u64(9) }
	mut counter := if failure == 16 { ~u32(0) - 31 } else { u32(5) }
	old_threshold, old_counter := threshold, counter
	queue.threshold = SharedBuffer{ phys: unsafe { u64(&threshold) }, size: sizeof(threshold) }
	queue.render_buffer.counter = SharedBuffer{ phys: unsafe { u64(&counter) }, size: sizeof(counter) }
	mut expected := [3][1280]u64{}
	mut counts := [3]u32{}
	mut renders := u32(0)
	mut bound := u32(0)
	if failure == 15 { bound = 2 }
	for pipe in 0 .. 3 {
		// Exactly one free outer entry must suffice for the complete batch.
		headers[pipe].read_ptr, headers[pipe].write_ptr = 1, 3
		states[pipe].cpu_wptr, states[pipe].gpu_doneptr, states[pipe].cpu_freeptr = 1278, 1278, 1277
		mgr.channels.pipes[pipe] = channel.new_tx_channel('batch', 1, unsafe { u64(&headers[pipe]) }, 1,
			unsafe { u64(&messages[pipe]) }, 4, u32(sizeof(fw.FwRunWorkQueueMsg)))
		queue.subqueues[pipe].state = SharedBuffer{ phys: unsafe { u64(&states[pipe]) }, size: sizeof(fw.G13WorkQueueRingState) }
		queue.subqueues[pipe].ring = SharedBuffer{ phys: unsafe { u64(&rings[pipe]) }, size: 1280 * sizeof(u64) }
		queue.subqueues[pipe].info.va = 0x100000 + u64(pipe) * 0x10000
		queue.subqueues[pipe].is_new = true
	}
	for index in 0 .. job_count {
		render := shape == 1 || (shape == 2 && index % 2 == 1)
		jobs[index] = initial_job(mut mgr, mut queue, &context, unsafe { &completions[index] }, render)
		base := alloc.g13_gpu_readonly_start + u64(index) * 0x10000
		prefixes := u32(index % 3)
		if render {
			mut job := unsafe { jobs[index].render }
			job.vertex.va, job.fragment.va, job.barrier.va = base, base + 0x1000, base + 0x2000
			job.init_buffer = SharedBuffer{ va: base + 0x4000, size: 0x1000 }
			job.explicit_barriers = G13CommandBarriers{ count: prefixes, offset: 0x80 }
			blocks := if index >= 32 { u32(2) } else { u32(1) }
			job.tvb_size_bytes = u64(blocks) * fw.g13_tvb_block_size
			for prefix := u32(0); prefix < prefixes; prefix++ {
				expected[0][(1278 + counts[0]) % 1280] = base + 0x4080 + u64(prefix) * 0x80
				counts[0]++
			}
			if bound < blocks {
				expected[0][(1278 + counts[0]) % 1280] = base + 0x4000
				counts[0]++
				bound = blocks
			}
			expected[0][(1278 + counts[0]) % 1280] = base
			counts[0]++
			expected[1][(1278 + counts[1]) % 1280] = base + 0x2000
			expected[1][(1279 + counts[1]) % 1280] = base + 0x1000
			counts[1] += 2
			renders++
		} else {
			mut job := unsafe { jobs[index].compute }
			job.command.va = base
			job.microsequence = SharedBuffer{ phys: 2, va: base + 0x4000, size: 0x1000 }
			job.explicit_barriers = G13CommandBarriers{ count: prefixes, offset: 0x80 }
			for prefix := u32(0); prefix < prefixes; prefix++ {
				expected[2][(1278 + counts[2]) % 1280] = base + 0x4080 + u64(prefix) * 0x80
				counts[2]++
			}
			expected[2][(1278 + counts[2]) % 1280] = base
			counts[2]++
		}
	}
	for index := canceled_count - 1; index >= 0; index-- { initial_discard(mut mgr, canceled[index]) }
	if failure == 15 { queue.render_buffer.needs_bind, queue.render_buffer.bound_blocks = false, 2 }
	last_pipe := if shape == 1 { 1 } else { 2 }
	match failure {
		1 { headers[last_pipe].read_ptr = 0 }
		2 { headers[last_pipe].write_ptr = 4 }
		3 { states[last_pipe].gpu_doneptr = 1 }
		4 { states[last_pipe].gpu_doneptr = 1280 }
		5 {
			if jobs[63].compute != unsafe { nil } { unsafe { jobs[63].compute.command.va = 0 } }
			else { unsafe { jobs[63].render.fragment.va = 0 } }
		}
		6 { mgr.pending_missing = true }
		7 { mgr.batch_pending = ~u32(0) - 63 }
		8 { mgr.kick_fails = true }
		9 { queue.subqueues[last_pipe].retired_sequence = 1 }
		10 { context.active = false }
		11 { jobs[0], jobs[2] = jobs[2], jobs[0] }
		12 { states[last_pipe].cpu_freeptr = 1280 }
		13 { queue.channel_mask &= ~(u32(1) << last_pipe) }
		14 { mgr.doorbell_fail = last_pipe }
		18 { mgr.channels.pipes[last_pipe].write_off = 0x1000 }
		else {}
	}
	old_pending := mgr.batch_pending
	mut offered := [64]G13SubmissionJob{}
	mut offered_count := u32(0)
	for index in 0 .. job_count {
		if failure == 17 && index == 30 { continue }
		offered[offered_count] = jobs[index]
		offered_count++
	}
	mut result := mgr.submit_g13_batch(offered, offered_count)
	refused := (failure > 0 && failure < 14) || failure == 17 || failure == 18
	if refused {
		assert result == 0 && mgr.batch_pending == old_pending && threshold == old_threshold && counter == old_counter
		assert mgr.doorbells.len == 0 && completions.all(it.calls == 0)
		for pipe in 0 .. 3 {
			assert states[pipe].cpu_wptr == 1278 && queue.subqueues[pipe].command_sequence == 0
			for value in rings[pipe] { assert value == 0 }
			for message in messages[pipe] { assert message.work_queue_addr == 0 }
			assert !queue.subqueues[pipe].lock.is_locked()
			assert !mgr.channels.pipes[pipe].lock.is_locked()
		}
		for index in 0 .. job_count { source := jobs[index]; assert if source.compute != unsafe { nil } { !source.compute.submitted } else { !source.render.submitted } }
		if failure == 1 || failure == 3 {
			headers[last_pipe].read_ptr = 1
			states[last_pipe].gpu_doneptr = 1278
			result = mgr.submit_g13_batch(jobs, 64)
		}
	}
	if result != 0 {
		assert result == if job_count == 64 { ~u64(0) } else { (u64(1) << job_count) - 1 }
		assert mgr.batch_pending == old_pending + u32(job_count)
		assert threshold == old_threshold + u64(job_count) + u64(renders) && counter == old_counter + renders
		assert mgr.state == if failure == 14 { State.error } else { State.running }
		mut notifications := []u32{}
		for pipe in [1, 0, 2]! { if counts[pipe] != 0 { notifications << u32(pipe) } }
		assert mgr.doorbells == notifications
		for pipe in 0 .. 3 {
			assert rings[pipe] == expected[pipe]
			assert queue.subqueues[pipe].command_sequence == counts[pipe]
			if counts[pipe] == 0 { assert headers[pipe].write_ptr == 3; continue }
			assert headers[pipe].write_ptr == 0 && states[pipe].cpu_wptr == (1278 + counts[pipe]) % 1280
			assert messages[pipe][3].write_ptr == states[pipe].cpu_wptr
			assert messages[pipe][3].is_new == 1 && messages[pipe][3].pipe_type == u32(pipe)
			assert messages[pipe][3].work_queue_addr == queue.subqueues[pipe].info.va
		}
		for index in 0 .. job_count {
			source := jobs[index]
			if source.compute != unsafe { nil } { driver[source.compute.event_slot] = source.compute.stamp_value }
			else { driver[source.render.vertex_event_slot] = source.render.vertex_stamp_value; driver[source.render.fragment_event_slot] = source.render.fragment_stamp_value }
		}
		mgr.pending = job_count
		mgr.reap_g13_compute_jobs()
		mgr.reap_g13_render_jobs()
		assert mgr.batch_pending == old_pending && mgr.pending == 0
	} else {
		for index := job_count - 1; index >= 0; index-- { initial_discard(mut mgr, jobs[index]) }
	}
	if mgr.state == .error || !context.active {
		if mgr.state == .error { assert mgr.g13_compute_jobs.len + mgr.g13_render_jobs.len == job_count, 'error must retain backing until firmware stops' }
		mgr.state = .stopped
		mgr.release_all_g13_compute_jobs()
		mgr.release_all_g13_render_jobs()
	}
	for index in 0 .. job_count { assert completions[index].calls == 1 }
	for index in 0 .. canceled_count { assert canceled_done[index].calls == 1 }
	assert mgr.g13_compute_jobs.len == 0 && mgr.g13_render_jobs.len == 0, 'shape=${shape} failure=${failure}'
	assert !queue.subqueues[0].events.busy() && !queue.subqueues[1].events.busy() && !queue.subqueues[2].events.busy(), 'event ownership shape=${shape} failure=${failure}'
	expect_free_events(128, -1)
	event.reset_event_manager()
}
