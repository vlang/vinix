// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.fw

// Borrow prepared jobs synchronously, before any pointer transfers to firmware.
// The single file poller and per-queue publication FIFO exclude another batch
// consuming this queue's capacity between admission and publication. Reapers
// only increase capacity. Individual publishers still check every actual write.
pub fn (mut mgr GpuManager) g13_batch_ready(jobs [64]G13SubmissionJob, count u32) bool {
	mgr.lock.acquire()
	defer { mgr.lock.release() }
	if mgr.state != .running || count == 0 || count > 64 { return false }
	mut queue := &G13QueueResources(unsafe { nil })
	mut events := [3]u32{}
	mut commands := [3]u32{}
	mut needs_bind := false
	mut bound_blocks := u32(0)
	for index := u32(0); index < count; index++ {
		source := jobs[index]
		if (source.render == unsafe { nil }) == (source.compute == unsafe { nil }) { return false }
		owner := if source.render != unsafe { nil } { source.render.queue } else { source.compute.queue }
		if owner == unsafe { nil } || owner.released || owner.quarantined { return false }
		if queue == unsafe { nil } {
			queue = owner
			if mgr.g13_queue_dispatch_blocked_locked(queue) { return false }
			needs_bind = queue.render_buffer.needs_bind
			bound_blocks = queue.render_buffer.bound_blocks
		} else if voidptr(queue) != voidptr(owner) { return false }
		if source.compute != unsafe { nil } {
			mut job := unsafe { source.compute }
			if job.released || job.submitted || job.quarantined || !job.event_reserved { return false }
			_ := queue.subqueues[2].events.ticket(job.event_slot, job.stamp_value) or { return false }
			if !mgr.resolve_g13_initial_barriers_locked(mut job.explicit_barriers, mut job.microsequence,
				queue, job.stamp_value) || !job.explicit_barriers.publishable(&job.microsequence) { return false }
			events[2]++
			commands[2] += 1 + job.explicit_barriers.count
		} else {
			mut job := unsafe { source.render }
			if job.released || job.submitted || job.quarantined || !job.vertex_event_reserved || !job.fragment_event_reserved { return false }
			_ := queue.subqueues[0].events.ticket(job.vertex_event_slot, job.vertex_stamp_value) or { return false }
			_ := queue.subqueues[1].events.ticket(job.fragment_event_slot, job.fragment_stamp_value) or { return false }
			if !mgr.resolve_g13_initial_barriers_locked(mut job.explicit_barriers, mut job.init_buffer,
				queue, job.vertex_stamp_value) || !job.explicit_barriers.publishable(&job.init_buffer) { return false }
			block_count := u32(job.tvb_size_bytes / fw.g13_tvb_block_size)
			include_init := needs_bind || bound_blocks < block_count
			commands[0] += job.explicit_barriers.count + if include_init { u32(2) } else { u32(1) }
			commands[1] += 2 // fragment barrier plus RunFragment
			events[0]++
			events[1]++
			if include_init {
				needs_bind = false
				bound_blocks = block_count
			}
		}
	}
	for pipe in 0 .. 3 {
		if events[pipe] == 0 { continue }
		if !queue.subqueues[pipe].events.can_submit(events[pipe])
			|| !mgr.g13_ring_has_space_locked(queue.subqueues[pipe].command_sequence,
				queue.subqueues[pipe].retired_sequence, commands[pipe]) { return false }
	}
	// Every ticket was validated above and no teardown can intervene under
	// this lock. Preserve this once-per-batch event grant across stamp gaps;
	// outer-ring retries still retain only the already prepared tickets.
	for index := u32(0); index < count; index++ {
		source := jobs[index]
		granted := if source.compute != unsafe { nil } {
			queue.subqueues[2].events.admit(source.compute.event_slot, source.compute.stamp_value)
		} else {
			queue.subqueues[0].events.admit(source.render.vertex_event_slot, source.render.vertex_stamp_value)
				&& queue.subqueues[1].events.admit(source.render.fragment_event_slot, source.render.fragment_stamp_value)
		}
		if !granted { mgr.state = .error; return false }
	}
	return true
}
