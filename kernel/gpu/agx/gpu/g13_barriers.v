// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.event
import gpu.agx.fw

const g13_barrier_stride = u64(0x80)
const g13_barrier_tail_size = g13_barrier_stride * 2

// Borrowed prepared jobs or an owned initial capture, read under manager.lock.
// No producer pointer is retained after its physical stamp is pinned.
pub struct G13BarrierSource {
pub:
	render  &G13RenderJobResources  = unsafe { nil }
	compute &G13ComputeJobResources = unsafe { nil }
	initial G13InitialEvent
}

// The records live in the tail of the existing command/init allocation.
// They share its mapping and backing lifetime.
struct G13CommandBarriers {
mut:
	offset     u64
	count      u32
	pin_count  u32
	slots      [2]u32
	waits      [2]G13BarrierWait
	initial_pending bool
	configured bool
	ready      bool
}

struct G13BarrierWait {
	ticket event.Ticket
	pipe u32
	initial bool
}

fn g13_barrier_tail_offset(active_size u64) u64 {
	return (active_size + g13_barrier_stride - 1) & ~(g13_barrier_stride - 1)
}

fn (barriers &G13CommandBarriers) publishable(owner &SharedBuffer) bool {
	if barriers.count > 2 || barriers.initial_pending || (barriers.configured && !barriers.ready) { return false }
	if barriers.count == 0 { return true }
	return owner.va != 0 && barriers.offset != 0 && barriers.offset <= owner.size
		&& g13_barrier_tail_size <= owner.size - barriers.offset
}

fn g13_barrier_source(source G13BarrierSource, queue &G13QueueResources) ?event.Ticket {
	if source.initial.valid {
		if source.render != unsafe { nil } || source.compute != unsafe { nil } || voidptr(source.initial.queue) != voidptr(queue) { return none }
		return source.initial.ticket
	}
	if source.render != unsafe { nil } && source.compute != unsafe { nil } { return none }
	if source.render != unsafe { nil } {
		job := source.render
		if job.released || job.submitted || job.quarantined || !job.fragment_event_reserved || voidptr(job.queue) != voidptr(queue) {
			return none
		}
		return event.Ticket{ slot: job.fragment_event_slot, value: job.fragment_stamp_value }
	}
	if source.compute != unsafe { nil } {
		job := source.compute
		if job.released || job.submitted || job.quarantined || !job.event_reserved || voidptr(job.queue) != voidptr(queue) {
			return none
		}
		return event.Ticket{ slot: job.event_slot, value: job.stamp_value }
	}
	return none
}

fn write_g13_barrier(owner &SharedBuffer, offset u64, index u32, wait event.Ticket, stamp_self u32) {
	unsafe {
		mut command := &fw.G13BarrierCommand(voidptr(u64(owner.cpu_address()) + offset + u64(index) * g13_barrier_stride))
		*command = fw.G13BarrierCommand{
			tag: fw.cmd_type_barrier
			wait_stamp: event.firmware_stamp_address(wait.slot)
			wait_value: wait.value
			wait_slot: wait.slot
			stamp_self: stamp_self
			uuid: 0xffffbbbb
			external_barrier: 0
			internal_barrier_type: 1
		}
	}
}

// Caller holds manager.lock. Store every pin before the next fallible step;
// any failure is unwound by the consumer's normal graph cleanup or quarantine.
fn initialize_g13_barriers_locked(mut barriers G13CommandBarriers,
	owner &SharedBuffer, queue &G13QueueResources, stamp_self u32, sources [2]G13BarrierSource) bool {
	if barriers.configured || owner.phys == 0 || owner.va == 0 || barriers.offset == 0
		|| barriers.offset > owner.size || g13_barrier_tail_size > owner.size - barriers.offset {
		return false
	}
	barriers.configured = true
	for pipe, source in sources {
		if source.render == unsafe { nil } && source.compute == unsafe { nil } && !source.initial.valid { continue }
		if source.initial.valid && source.initial.pipe != u32(pipe) { return false }
		wait := g13_barrier_source(source, queue) or { return false }
		if !event.retain_stamp(wait.slot) { return false }
		index := barriers.count
		barriers.slots[index] = wait.slot
		barriers.waits[index] = G13BarrierWait{ ticket: wait, pipe: u32(pipe), initial: source.initial.valid }
		barriers.pin_count++
		barriers.initial_pending = barriers.initial_pending || source.initial.valid
		barriers.count++
		write_g13_barrier(owner, barriers.offset, index, wait, stamp_self)
	}
	// Submission orders these stores before publishing the ring pointers.
	barriers.ready = true
	return true
}

// Resolve once immediately before publication. Immutable waits and pin_count
// survive compaction; omitted records retain their pins until
// the complete consuming graph is invalidated or firmware stops.
fn (mut mgr GpuManager) resolve_g13_initial_barriers_locked(mut barriers G13CommandBarriers,
	mut owner SharedBuffer, queue &G13QueueResources, stamp_self u32) bool {
	if !barriers.initial_pending { return true }
	if mgr.state != .running || !barriers.ready || barriers.pin_count > 2 || owner.phys == 0 || owner.va == 0
		|| barriers.offset == 0 || barriers.offset > owner.size || g13_barrier_tail_size > owner.size - barriers.offset { return false }
	mut resolved := [2]event.Ticket{}
	mut count := u32(0)
	for index := u32(0); index < barriers.pin_count; index++ {
		wait := barriers.waits[index]
		mut target := wait.ticket
		if wait.initial {
			physical := if wait.pipe == 0 { 1 } else { 2 }
			state, ticket := queue.subqueues[physical].events.resolve_initial(wait.ticket)
			if state == .pending { return false }
			if state == .absent { continue }
			target = ticket
		}
		resolved[count] = target
		count++
	}
	for index := u32(0); index < count; index++ { write_g13_barrier(&owner, barriers.offset, index, resolved[index], stamp_self) }
	barriers.count = count
	barriers.initial_pending = false
	return true
}

pub fn (mut mgr GpuManager) set_g13_compute_barriers(job &G13ComputeJobResources, sources [2]G13BarrierSource) bool {
	if job == unsafe { nil } { return false }
	mgr.lock.acquire()
	defer { mgr.lock.release() }
	mut owned := unsafe { job }
	if mgr.state != .running || owned.released || owned.submitted || owned.quarantined
		|| !owned.event_reserved || owned.queue == unsafe { nil } || owned.queue.released || owned.queue.quarantined {
		return false
	}
	return initialize_g13_barriers_locked(mut owned.explicit_barriers, &owned.microsequence,
		owned.queue, owned.stamp_value, sources)
}

pub fn (mut mgr GpuManager) set_g13_render_barriers(job &G13RenderJobResources, sources [2]G13BarrierSource) bool {
	if job == unsafe { nil } { return false }
	mgr.lock.acquire()
	defer { mgr.lock.release() }
	mut owned := unsafe { job }
	if mgr.state != .running || owned.released || owned.submitted || owned.quarantined
		|| !owned.vertex_event_reserved || owned.queue == unsafe { nil } || owned.queue.released || owned.queue.quarantined {
		return false
	}
	return initialize_g13_barriers_locked(mut owned.explicit_barriers, &owned.init_buffer,
		owned.queue, owned.vertex_stamp_value, sources)
}

// Called only after the entire owner graph has passed invalidation, or after
// firmware stops. The producer's own event reference may already be gone.
fn release_g13_barrier_pins(mut barriers G13CommandBarriers) {
	for index := u32(0); index < barriers.pin_count; index++ {
		event.release_stamp(barriers.slots[index])
	}
	barriers.count = 0
	barriers.pin_count = 0
	barriers.initial_pending = false
	barriers.ready = false
}
