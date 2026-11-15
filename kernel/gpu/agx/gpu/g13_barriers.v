// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.event
import gpu.agx.fw

const g13_barrier_stride = u64(0x80)
const g13_barrier_tail_size = g13_barrier_stride * 2

// Borrowed prepared jobs, read only under manager.lock during setup. No job
// pointer is retained in the consumer after its physical stamp is pinned.
pub struct G13BarrierSource {
pub:
	render  &G13RenderJobResources  = unsafe { nil }
	compute &G13ComputeJobResources = unsafe { nil }
}

// The records live in the tail of the existing command/init allocation.
// They share its flush/invalidate/free gate and introduce no new allocation.
struct G13CommandBarriers {
mut:
	offset     u64
	count      u32
	slots      [2]u32
	configured bool
	ready      bool
}

fn g13_barrier_tail_offset(active_size u64) u64 {
	return (active_size + g13_barrier_stride - 1) & ~(g13_barrier_stride - 1)
}

fn (barriers &G13CommandBarriers) publishable(owner &SharedBuffer) bool {
	if barriers.count > 2 || (barriers.configured && !barriers.ready) { return false }
	if barriers.count == 0 { return true }
	return owner.va != 0 && barriers.offset != 0 && barriers.offset <= owner.size
		&& g13_barrier_tail_size <= owner.size - barriers.offset
}

fn g13_barrier_source(source &G13BarrierSource, queue &G13QueueResources) ?event.Ticket {
	if source.render != unsafe { nil } && source.compute != unsafe { nil } { return none }
	if source.render != unsafe { nil } {
		job := source.render
		if job.released || job.submitted || job.quarantined || !job.fragment_event_reserved || job.queue != queue {
			return none
		}
		return event.Ticket{ slot: job.fragment_event_slot, value: job.fragment_stamp_value }
	}
	if source.compute != unsafe { nil } {
		job := source.compute
		if job.released || job.submitted || job.quarantined || !job.event_reserved || job.queue != queue {
			return none
		}
		return event.Ticket{ slot: job.event_slot, value: job.stamp_value }
	}
	return none
}

// Caller holds manager.lock. Store every pin before the next fallible step;
// any failure is unwound by the consumer's normal graph cleanup or quarantine.
fn (mut mgr GpuManager) initialize_g13_barriers_locked(mut barriers G13CommandBarriers,
	mut owner SharedBuffer, queue &G13QueueResources, stamp_self u32, sources [2]G13BarrierSource) bool {
	if barriers.configured || owner.phys == 0 || barriers.offset == 0
		|| barriers.offset > owner.size || g13_barrier_tail_size > owner.size - barriers.offset {
		return false
	}
	barriers.configured = true
	for source in sources {
		if source.render == unsafe { nil } && source.compute == unsafe { nil } { continue }
		wait := g13_barrier_source(unsafe { &source }, queue) or { return false }
		if !event.retain_stamp(wait.slot) { return false }
		index := barriers.count
		barriers.slots[index] = wait.slot
		barriers.count++
		unsafe {
			mut command := &fw.G13BarrierCommand(voidptr(u64(owner.cpu_address()) + barriers.offset + u64(index) * g13_barrier_stride))
			*command = fw.G13BarrierCommand{
				tag:                   fw.cmd_type_barrier
				wait_stamp:            event.firmware_stamp_address(wait.slot)
				wait_value:            wait.value
				wait_slot:             wait.slot
				stamp_self:            stamp_self
				uuid:                  0xffffbbbb
				external_barrier:      0
				internal_barrier_type: 1
			}
		}
	}
	if barriers.count != 0 && !mgr.flush_g13_kernel_buffer(&owner) { return false }
	barriers.ready = true
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
	return mgr.initialize_g13_barriers_locked(mut owned.explicit_barriers, mut owned.microsequence,
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
	return mgr.initialize_g13_barriers_locked(mut owned.explicit_barriers, mut owned.init_buffer,
		owned.queue, owned.vertex_stamp_value, sources)
}

// Called only after the entire owner graph has passed invalidation, or after
// firmware stops. The producer's own event reference may already be gone.
fn release_g13_barrier_pins(mut barriers G13CommandBarriers) {
	for index := u32(0); index < barriers.count; index++ {
		event.release_stamp(barriers.slots[index])
	}
	barriers.count = 0
	barriers.ready = false
}
