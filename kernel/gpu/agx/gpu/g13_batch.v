// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.alloc
import gpu.agx.fw
import katomic

struct G13BatchPipe {
mut:
	count u32
	events u32
	values [64]u32
	last_value u32
	slot u32
	outer_wp u32
	outer_next u32
	inner_next u32
}

struct G13BatchDoorbells {
	priority u32
	pipes    u32
}

fn g13_batch_address(address u64) bool {
	return (address >= alloc.g13_gpu_readonly_start && address < alloc.g13_gpu_readonly_end)
		|| (address >= alloc.g13_private_start && address < alloc.g13_private_end)
}

// No pointer or ownership escapes on zero. A returned bit transfers that job's
// complete graph, even if notification fails after publication. Native batches
// transfer all jobs together; the mask also lets the caller handle a backend
// that transfers only a prefix without ever dereferencing transferred metadata.
pub fn (mut mgr GpuManager) submit_g13_batch(jobs [64]G13SubmissionJob, count u32, operation_active bool) u64 {
	mgr.lock.acquire()
	defer { mgr.lock.release() }
	doorbells := mgr.publish_g13_batch_locked(jobs, count, operation_active) or { return 0 }
	// The reaper may retire the submitted jobs while the mailbox waits. Only
	// the scalar doorbells and count are used after publication returns.
	for pipe in [1, 0, 2]! {
		if doorbells.pipes & (u32(1) << pipe) == 0 { continue }
		if !mgr.ring_g13_batch_pipe_locked(doorbells.priority, u32(pipe)) {
			if mgr.state == .running { mgr.state = .error }
			break
		}
	}
	return if count == 64 { ~u64(0) } else { (u64(1) << count) - 1 }
}

fn (mut mgr GpuManager) publish_g13_batch_locked(jobs [64]G13SubmissionJob, count u32,
	operation_active bool) ?G13BatchDoorbells {
	if mgr.hw_config.gpu_gen != .g13 || !mgr.admit_g13_batch_locked(jobs, count) { return none }
	mut queue := unsafe { if jobs[0].render != nil { jobs[0].render.queue } else { jobs[0].compute.queue } }
	if queue.priority >= 4 || mgr.g13_channels == unsafe { nil } || queue.threshold.phys == 0
		|| queue.threshold.size < sizeof(u64) { return none }
	mut pipes := [3]G13BatchPipe{}
	mut binds := [64]bool{}
	mut needs_bind := queue.render_buffer.needs_bind
	mut bound_blocks := queue.render_buffer.bound_blocks
	mut renders := u32(0)
	for index := u32(0); index < count; index++ {
		source := jobs[index]
		if source.compute != unsafe { nil } {
			job := source.compute
			if job.context == unsafe { nil } || !job.context.active || !g13_batch_address(job.command.va) { return none }
			for prefix := u32(0); prefix < job.explicit_barriers.count; prefix++ {
				if !g13_batch_address(job.microsequence.va + job.explicit_barriers.offset + u64(prefix) * g13_barrier_stride) { return none }
			}
			if pipes[2].count != 0 && i32(job.stamp_value - pipes[2].last_value) <= 0 { return none }
			pipes[2].last_value, pipes[2].slot = job.stamp_value, job.event_slot
			pipes[2].values[pipes[2].events] = job.stamp_value
			pipes[2].events++
			pipes[2].count += 1 + job.explicit_barriers.count
		} else {
			job := source.render
			if job.context == unsafe { nil } || !job.context.active || !g13_batch_address(job.vertex.va)
				|| !g13_batch_address(job.fragment.va) || !g13_batch_address(job.barrier.va) { return none }
			block_count := u32(job.tvb_size_bytes / fw.g13_tvb_block_size)
			binds[index] = needs_bind || bound_blocks < block_count
			if binds[index] {
				if !g13_batch_address(job.init_buffer.va) { return none }
				needs_bind, bound_blocks = false, block_count
			}
			for prefix := u32(0); prefix < job.explicit_barriers.count; prefix++ {
				if !g13_batch_address(job.init_buffer.va + job.explicit_barriers.offset + u64(prefix) * g13_barrier_stride) { return none }
			}
			if pipes[0].count != 0 && (i32(job.vertex_stamp_value - pipes[0].last_value) <= 0
				|| i32(job.fragment_stamp_value - pipes[1].last_value) <= 0) { return none }
			pipes[0].last_value, pipes[0].slot = job.vertex_stamp_value, job.vertex_event_slot
			pipes[1].last_value, pipes[1].slot = job.fragment_stamp_value, job.fragment_event_slot
			pipes[0].values[pipes[0].events], pipes[1].values[pipes[1].events] = job.vertex_stamp_value, job.fragment_stamp_value
			pipes[0].events++
			pipes[1].events++
			pipes[0].count += job.explicit_barriers.count + if binds[index] { u32(2) } else { u32(1) }
			pipes[1].count += 2
			renders++
		}
	}
	if renders != 0 && (queue.render_buffer.counter.phys == 0 || queue.render_buffer.counter.size < sizeof(u32)) { return none }
	for pipe in 0 .. 3 {
		if pipes[pipe].count == 0 { continue }
		if queue.channel_mask & (u32(1) << pipe) == 0
			|| !queue.subqueues[pipe].events.can_publish_batch(pipes[pipe].slot, pipes[pipe].values, pipes[pipe].events) { return none }
	}
	// Lock every participating ring before preparing any of them. The order
	// agrees with the standalone paired publisher; manager.lock excludes reapers.
	for pipe in 0 .. 3 {
		if pipes[pipe].count != 0 { mgr.channels.pipes[pipe_index(queue.priority, u32(pipe))].lock.acquire() }
	}
	for pipe in 0 .. 3 { if pipes[pipe].count != 0 { queue.subqueues[pipe].lock.acquire() } }
	defer {
		for pipe := 2; pipe >= 0; pipe-- { if pipes[pipe].count != 0 { queue.subqueues[pipe].lock.release() } }
		for pipe := 2; pipe >= 0; pipe-- {
			if pipes[pipe].count != 0 { mgr.channels.pipes[pipe_index(queue.priority, u32(pipe))].lock.release() }
		}
	}
	for pipe in 0 .. 3 {
		if pipes[pipe].count == 0 { continue }
		mut outer := &mgr.channels.pipes[pipe_index(queue.priority, u32(pipe))]
		inner := &queue.subqueues[pipe]
		if outer.state_phys == 0 || outer.ring_phys == 0 || outer.ring_size < 2
			|| outer.entry_size != sizeof(fw.FwRunWorkQueueMsg) || outer.write_off != 0x20 || inner.state.phys == 0
			|| inner.state.size < sizeof(fw.G13WorkQueueRingState) || inner.ring.phys == 0
			|| inner.ring.size < u64(fw.g13_workqueue_entries) * sizeof(u64) || inner.info.va == 0 { return none }
		outer_rp := unsafe { katomic.load(&u32(outer.state_phys + higher_half)) }
		outer_wp := unsafe { katomic.load(&u32(outer.state_phys + higher_half + outer.write_off)) }
		if !outer.validate_pointers(outer_rp, outer_wp) { mgr.state = .error; return none }
		pipes[pipe].outer_wp = outer_wp
		pipes[pipe].outer_next = (outer_wp + 1) % outer.ring_size
		if pipes[pipe].outer_next == outer_rp { return none }
		state := unsafe { &fw.G13WorkQueueRingState(inner.state.cpu_address()) }
		wp, done, free := katomic.load(&state.cpu_wptr), katomic.load(&state.gpu_doneptr), katomic.load(&state.cpu_freeptr)
		if wp >= fw.g13_workqueue_entries || done >= fw.g13_workqueue_entries || free >= fw.g13_workqueue_entries {
			mgr.state = .error
			return none
		}
		used := (wp + fw.g13_workqueue_entries - done) % fw.g13_workqueue_entries
		if pipes[pipe].count > fw.g13_workqueue_entries - used - 1 { return none }
		pipes[pipe].inner_next = wp
	}
	if !operation_active && !mgr.begin_g13_operation_locked() { return none }
	// All fallible preparation is finished before notifier accounting or the
	// first visible pointer. The pending submission owns the operation once
	// any work is published, including after a doorbell error.
	mut threshold := unsafe { &u64(queue.threshold.cpu_address()) }
	katomic.store(mut threshold, katomic.load(threshold) + u64(count) + u64(renders))
	if renders != 0 {
		mut counter := unsafe { &u32(queue.render_buffer.counter.cpu_address()) }
		katomic.store(mut counter, katomic.load(counter) + renders)
	}
	for index := u32(0); index < count; index++ {
		source := jobs[index]
		if source.compute != unsafe { nil } {
			mut job := unsafe { source.compute }
			for prefix := u32(0); prefix < job.explicit_barriers.count; prefix++ {
				append_g13_batch_command(queue, 2, unsafe { &pipes[2] }, job.microsequence.va + job.explicit_barriers.offset + u64(prefix) * g13_barrier_stride)
			}
			append_g13_batch_command(queue, 2, unsafe { &pipes[2] }, job.command.va)
			job.ring_slot, job.retirement_sequence = queue.subqueues[2].last_command_slot, queue.subqueues[2].command_sequence
			job.submitted = true
			if !queue.subqueues[2].events.publish(job.event_slot, job.stamp_value) { mgr.state = .error }
		} else {
			mut job := unsafe { source.render }
			for prefix := u32(0); prefix < job.explicit_barriers.count; prefix++ {
				append_g13_batch_command(queue, 0, unsafe { &pipes[0] }, job.init_buffer.va + job.explicit_barriers.offset + u64(prefix) * g13_barrier_stride)
			}
			if binds[index] { append_g13_batch_command(queue, 0, unsafe { &pipes[0] }, job.init_buffer.va) }
			append_g13_batch_command(queue, 0, unsafe { &pipes[0] }, job.vertex.va)
			append_g13_batch_command(queue, 1, unsafe { &pipes[1] }, job.barrier.va)
			append_g13_batch_command(queue, 1, unsafe { &pipes[1] }, job.fragment.va)
			job.vertex_ring_slot, job.vertex_retirement_sequence = queue.subqueues[0].last_command_slot, queue.subqueues[0].command_sequence
			job.fragment_ring_slot, job.fragment_retirement_sequence = queue.subqueues[1].last_command_slot, queue.subqueues[1].command_sequence
			job.submitted = true
			if !queue.subqueues[0].events.publish(job.vertex_event_slot, job.vertex_stamp_value)
				|| !queue.subqueues[1].events.publish(job.fragment_event_slot, job.fragment_stamp_value) { mgr.state = .error }
		}
	}
	if renders != 0 { queue.render_buffer.needs_bind, queue.render_buffer.bound_blocks = needs_bind, bound_blocks }
	for pipe in 0 .. 3 {
		if pipes[pipe].count == 0 { continue }
		outer := &mgr.channels.pipes[pipe_index(queue.priority, u32(pipe))]
		mut inner := &queue.subqueues[pipe]
		unsafe {
			mut destination := &fw.FwRunWorkQueueMsg(outer.ring_phys + higher_half + u64(pipes[pipe].outer_wp) * outer.entry_size)
			*destination = fw.FwRunWorkQueueMsg{ pipe_type: u32(pipe), work_queue_addr: inner.info.va,
				write_ptr: pipes[pipe].inner_next, event_slot: pipes[pipe].slot, is_new: if inner.is_new { u32(1) } else { u32(0) } }
		}
		inner.is_new = false
	}
	katomic.sync()
	mut pipe_mask := u32(0)
	for pipe in [1, 0, 2]! {
		if pipes[pipe].count == 0 { continue }
		mut state := unsafe { &fw.G13WorkQueueRingState(queue.subqueues[pipe].state.cpu_address()) }
		katomic.store(mut &state.cpu_wptr, pipes[pipe].inner_next)
	}
	katomic.sync()
	for pipe in [1, 0, 2]! {
		if pipes[pipe].count == 0 { continue }
		mut outer := &mgr.channels.pipes[pipe_index(queue.priority, u32(pipe))]
		outer.publish_write_pointer_locked(pipes[pipe].outer_next)
		pipe_mask |= u32(1) << pipe
	}
	return G13BatchDoorbells{priority: queue.priority, pipes: pipe_mask}
}

fn append_g13_batch_command(queue &G13QueueResources, pipe int, plan &G13BatchPipe, address u64) {
	mut owned := unsafe { queue }
	mut cursor := unsafe { plan }
	mut inner := &owned.subqueues[pipe]
	unsafe { *(&u64(inner.ring.phys + higher_half + u64(cursor.inner_next) * sizeof(u64))) = address }
	inner.last_command_slot = cursor.inner_next
	inner.command_sequence++
	cursor.inner_next = (cursor.inner_next + 1) % fw.g13_workqueue_entries
}
