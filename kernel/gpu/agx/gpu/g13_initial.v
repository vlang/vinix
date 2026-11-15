// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.event

// Borrowed only for synchronous acceptance under manager.lock.
pub struct G13SubmissionJob {
pub:
	render  &G13RenderJobResources  = unsafe { nil }
	compute &G13ComputeJobResources = unsafe { nil }
}

// A capture owns one physical pin while valid; queue.last state is weak.
pub struct G13InitialEvent {
pub:
	queue  &G13QueueResources = unsafe { nil }
	ticket event.Ticket
	pipe   u32
	valid  bool
}

pub struct G13InitialEvents {
pub mut:
	values [2]G13InitialEvent
}

fn (mut mgr GpuManager) accept_g13_submission_locked(jobs [64]G13SubmissionJob, count u32) bool {
	if count == 0 || count > 64 { return false }
	mut queue := &G13QueueResources(unsafe { nil })
	mut last := [2]G13InitialEvent{}
	for index := u32(0); index < count; index++ {
		source := jobs[index]
		if (source.render == unsafe { nil }) == (source.compute == unsafe { nil }) { return false }
		mut owner := &G13QueueResources(unsafe { nil })
		mut slot := u32(0)
		mut value := u32(0)
		pipe := if source.render != unsafe { nil } { 0 } else { 1 }
		if pipe == 0 {
			job := source.render
			if job.released || job.submitted || job.quarantined || !job.vertex_event_reserved || !job.fragment_event_reserved {
				return false
			}
			owner, slot, value = job.queue, job.fragment_event_slot, job.fragment_stamp_value
		} else {
			job := source.compute
			if job.released || job.submitted || job.quarantined || !job.event_reserved {
				return false
			}
			owner, slot, value = job.queue, job.event_slot, job.stamp_value
		}
		if owner == unsafe { nil } || owner.released || owner.quarantined { return false }
		if queue == unsafe { nil } {
			queue = owner
		} else if voidptr(queue) != voidptr(owner) {
			return false
		}
		physical := if pipe == 0 { 1 } else { 2 }
		if pipe == 0 {
			_ := owner.subqueues[0].events.ticket(source.render.vertex_event_slot, source.render.vertex_stamp_value) or { return false }
		}
		ticket := owner.subqueues[physical].events.ticket(slot, value) or { return false }
		last[pipe] = G13InitialEvent{ queue: owner, ticket: ticket, pipe: u32(pipe), valid: true }
	}
	// Validation finishes before any accepted state changes. Enqueue follows
	// under the same lock, so rejected or partially prepared jobs never appear.
	for pipe in 0 .. 2 { if last[pipe].valid { queue.initial_events[pipe] = last[pipe] } }
	return true
}

pub fn (mut mgr GpuManager) capture_g13_initial_events(queue &G13QueueResources, mask u32) ?G13InitialEvents {
	mgr.lock.acquire()
	defer { mgr.lock.release() }
	if mgr.state != .running || !mgr.g13_events.initialized || queue == unsafe { nil }
		|| queue.released || queue.quarantined || mask & ~u32(3) != 0 {
		return none
	}
	mut capture := G13InitialEvents{}
	for pipe in 0 .. 2 {
		if mask & (u32(1) << pipe) == 0 { continue }
		last := queue.initial_events[pipe]
		physical := if pipe == 0 { 1 } else { 2 }
		if !last.valid || voidptr(last.queue) != voidptr(queue) || last.pipe != u32(pipe)
			|| !queue.subqueues[physical].events.owns_slot(last.ticket.slot) {
			continue
		}
		if !event.retain_stamp(last.ticket.slot) {
			for prior in capture.values {
				if prior.valid { event.release_stamp(prior.ticket.slot) }
			}
			return none
		}
		capture.values[pipe] = last
	}
	return capture
}

pub fn (mut mgr GpuManager) release_g13_initial_events(mut capture G13InitialEvents) {
	mgr.lock.acquire()
	defer { mgr.lock.release() }
	for mut value in capture.values {
		// A stopped manager may have reset/freed its stamp arrays. Never apply
		// an old capture's release to a newly initialized global manager.
		if value.valid && mgr.g13_events.initialized { event.release_stamp(value.ticket.slot) }
		value = G13InitialEvent{}
	}
}
