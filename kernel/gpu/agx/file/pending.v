// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module file

import drm.syncobj
import drm.ioctl
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.submission
import katomic
import klock
import memory

// Prepared jobs stay caller-owned until publication. Each callback retains
// this node through callbacks_remaining; one extra VM pin spans the whole
// submission, including gaps between command callbacks.
struct G13PendingCommand {
mut:
	compute_job &gpu.G13ComputeJobResources = unsafe { nil }
	render_job  &gpu.G13RenderJobResources  = unsafe { nil }
	pipe        u32
	initial_barriers u32
	wait_for    [2]u32 // command position + 1; zero has no in-batch dependency
	published   bool
	done        bool
	callback_finished bool // published after the callback releases its backing
	render_stage_finished [2]bool // private stage notifications; callbacks only publish
	stage_timestamps_released [2]bool // file-worker owned; one release per stage
	timestamps_released bool // worker-owned; independent of user fences
	error       i64 // explicit width selects the full native ARM atomic routine
}

struct G13PendingSubmission {
mut:
	next                &G13PendingSubmission = unsafe { nil }
	file                &GpuFile              = unsafe { nil }
	vm                  &mmu.UatContext = unsafe { nil }
	queue               &gpu.G13QueueResources = unsafe { nil }
	manager             &gpu.GpuManager        = unsafe { nil }
	timestamps          G13SubmissionTimestamps
	dependencies        submission.SyncArray
	dependencies_ready  bool
	operation_active    bool // one firmware operation per submission
	admitted            bool // scalar survives publication and immediate metadata retirement
	final_fence         &syncobj.DmaFence = unsafe { nil }
	commands            [64]G13PendingCommand
	command_count       u32
	callbacks_remaining u32
	failure             i64
}

__global pending_lock klock.Lock
__global pending_head &G13PendingSubmission = unsafe { nil }
__global pending_tail &G13PendingSubmission = unsafe { nil }
__global pending_count = u64(0)
__global pending_poll_active = false
__global pending_poll_requested = false

fn signal_g13_submission_fence(fence &syncobj.DmaFence, failure int) {
	if failure == 0 { syncobj.signal(fence) } else { syncobj.signal_error(fence, failure) }
}

// Resolve subqueue-local barrier indices while the staged input is alive.
// Index zero selects the captured prior subqueue event; other indices resolve
// to this batch's commands and installed firmware prefixes.
// Only integer positions survive; no staged payload or job pointer escapes.
fn resolve_g13_batch_dependencies(mut item G13PendingSubmission, commands []submission.Command) bool {
	if commands.len != int(item.command_count) { return false }
	mut positions := [2][64]u32{}
	mut counts := [2]u32{}
	for index := u32(0); index < item.command_count; index++ {
		mut entry := &item.commands[index]
		entry.pipe = if commands[index].descriptor.cmd_type == ioctl.asahi_cmd_render {
			u32(0)
		} else {
			u32(1)
		}
		for pipe in 0 .. 2 {
			barrier := commands[index].descriptor.barriers[pipe]
			if barrier == ioctl.asahi_barrier_none { continue }
			if barrier == 0 {
				entry.initial_barriers |= u32(1) << pipe
				continue
			}
			if barrier > counts[pipe] { return false }
			entry.wait_for[pipe] = positions[pipe][barrier - 1] + 1
		}
		positions[entry.pipe][counts[entry.pipe]] = index
		counts[entry.pipe]++
	}
	return true
}

fn g13_pending_error(item &G13PendingSubmission) int {
	for index := u32(0); index < item.command_count; index++ {
		command := &item.commands[index]
		if katomic.load(&command.done) {
			failure := katomic.load(&command.error)
			if failure != 0 { return int(failure) }
		}
	}
	return 0
}

// All source metadata remains caller-owned until this node is queued. The
// manager reads and pins its event slots while holding its publication lock.
fn install_g13_batch_barriers(mut item G13PendingSubmission, initial gpu.G13InitialEvents) bool {
	mut manager := unsafe { item.manager }
	for index := u32(0); index < item.command_count; index++ {
		command := &item.commands[index]
		mut sources := [2]gpu.G13BarrierSource{}
		for pipe in 0 .. 2 {
			dependency := command.wait_for[pipe]
			if dependency == 0 {
				if command.initial_barriers & (u32(1) << pipe) != 0 {
					sources[pipe] = gpu.G13BarrierSource{ initial: initial.values[pipe] }
				}
				continue
			}
			prior := &item.commands[dependency - 1]
			sources[pipe] = gpu.G13BarrierSource{ render: prior.render_job, compute: prior.compute_job }
		}
		installed := if command.compute_job != unsafe { nil } {
			manager.set_g13_compute_barriers(command.compute_job, sources)
		} else {
			manager.set_g13_render_barriers(command.render_job, sources)
		}
		if !installed { return false }
	}
	return true
}

fn register_g13_pending(mut manager gpu.GpuManager, item &G13PendingSubmission) ?&syncobj.DmaFence {
	mut jobs := [64]gpu.G13SubmissionJob{}
	for index := u32(0); index < item.command_count; index++ {
		jobs[index] = gpu.G13SubmissionJob{ render: item.commands[index].render_job, compute: item.commands[index].compute_job }
	}
	return manager.queue_g13_submission(jobs, item.command_count, enqueue_g13_pending, voidptr(item))
}

fn admit_g13_pending(mut manager gpu.GpuManager, item &G13PendingSubmission) bool {
	mut jobs := [64]gpu.G13SubmissionJob{}
	for index := u32(0); index < item.command_count; index++ {
		jobs[index] = gpu.G13SubmissionJob{ render: item.commands[index].render_job, compute: item.commands[index].compute_job }
	}
	return manager.g13_batch_ready(jobs, item.command_count)
}

fn submit_g13_pending(mut manager gpu.GpuManager, mut item G13PendingSubmission) {
	mut jobs := [64]gpu.G13SubmissionJob{}
	mut positions := [64]u32{}
	mut count := u32(0)
	for index := u32(0); index < item.command_count; index++ {
		command := &item.commands[index]
		if command.compute_job == unsafe { nil } && command.render_job == unsafe { nil } { continue }
		jobs[count] = gpu.G13SubmissionJob{ render: command.render_job, compute: command.compute_job }
		positions[count] = index
		count++
	}
	if count == 0 { return }
	transferred := manager.submit_g13_batch(jobs, count, item.operation_active)
	if transferred != 0 { item.operation_active = true }
	for index := u32(0); index < count; index++ {
		if transferred & (u64(1) << index) == 0 { continue }
		// Transferred metadata may already be freed. Clear values only.
		mut command := &item.commands[positions[index]]
		command.compute_job, command.render_job = unsafe { nil }, unsafe { nil }
		command.published = true
	}
}

// Called after acceptance under manager.lock while the ioctl still holds
// file.lock. Return the retained fence even if the worker retires the node.
fn enqueue_g13_pending(data voidptr) &syncobj.DmaFence {
	mut item := unsafe { &G13PendingSubmission(data) }
	assert item.next == unsafe { nil }
	mut queue := unsafe { item.queue }
	fence := syncobj.new_queue_fence(item.file.owner_key, u64(queue.next_fence_seqno()), queue.fence_context)
	item.final_fence = fence
	pending_lock.acquire()
	if pending_tail == unsafe { nil } { pending_head = item } else { pending_tail.next = item }
	pending_tail = item
	pending_count++
	pending_lock.release()
	return fence
}

// DRM scheduler dependencies order execution. A signaled input fence releases
// its wait even when it carries an error; only this submission's own work sets
// its completion error. The queue's own native fences are elided, as in its
// DRM scheduler entity; every other input still waits for actual signaling.
fn g13_dependencies_ready(dependencies &submission.SyncArray, queue_context u64) bool {
	for index := u32(0); index < dependencies.count; index++ {
		if !syncobj.queue_dependency_ready(dependencies.item(index).fence, queue_context) { return false }
	}
	return true
}

fn cancel_g13_pending(mut item G13PendingSubmission, failure int) {
	if katomic.load(&item.failure) == 0 { katomic.store(mut &item.failure, i64(failure)) }
	mut manager := unsafe { item.manager }
	// Reverse order refunds the newest unpublished event reservations first.
	for index := int(item.command_count) - 1; index >= 0; index-- {
		mut command := &item.commands[index]
		if command.compute_job != unsafe { nil } {
			job := command.compute_job
			command.compute_job = unsafe { nil }
			manager.release_g13_compute_job(job)
		}
		if command.render_job != unsafe { nil } {
			job := command.render_job
			command.render_job = unsafe { nil }
			manager.release_g13_render_job(job)
		}
	}
}

// Installed firmware prefixes order execution while all commands in this batch
// publish together. CPU callback/reaper order must not serialize GPU work.
// Across submissions, unpublished jobs retain FIFO order. Initial prefixes
// resolve under the publication lock without waiting for CPU retirement.
fn poll_g13_pending(mut item G13PendingSubmission) bool {
	mut manager := unsafe { item.manager }
	if manager.state != .running {
		cancel_g13_pending(mut item, -19)
		return katomic.load(&item.callbacks_remaining) != 0
	}
	if !item.dependencies_ready {
		if !g13_dependencies_ready(&item.dependencies, item.queue.fence_context) { return true }
		item.dependencies_ready = true
	}
	failure := g13_pending_error(item)
	if failure != 0 || katomic.load(&item.failure) != 0 {
		cancel_g13_pending(mut item, if failure != 0 {
			failure
		} else {
			int(katomic.load(&item.failure))
		})
		return katomic.load(&item.callbacks_remaining) != 0
	}
	if !item.admitted {
		if !admit_g13_pending(mut manager, item) {
			// Shutdown can finish every callback during this final readiness
			// check. Release caller-owned metadata before the node can retire.
			_ = katomic.load(&item.callbacks_remaining)
			if manager.state != .running {
				cancel_g13_pending(mut item, -19)
				return katomic.load(&item.callbacks_remaining) != 0
			}
			return true
		}
		item.admitted = true
	}
	if !manager.g13_queue_dispatch_blocked(item.queue) { submit_g13_pending(mut manager, mut item) }
	// A backend may complete transferred metadata before returning. Read the
	// node's callback state only after clearing every transferred pointer.
	completed_error := g13_pending_error(item)
	if completed_error != 0 { cancel_g13_pending(mut item, completed_error) }
	if katomic.load(&item.callbacks_remaining) != 0 { return true }
	// Acquiring zero callbacks observes shutdown's preceding state write.
	// Check afterward: stop may have run during the last publication or just
	// before this count load, leaving caller-owned prepared metadata behind.
	if manager.state != .running { cancel_g13_pending(mut item, -19) }
	// The last callback can run during publication. Read its error only after
	// acquiring the zero callback count, before allowing aggregate notification.
	final_error := g13_pending_error(item)
	if final_error != 0 { katomic.store(mut &item.failure, i64(final_error)) }
	return false
}

// Only the worker changes these pointers. A transferred or canceled job no
// longer prevents later submissions from entering the same firmware queues.
// Callbacks still retain this node and its VM pin until complete retirement.
fn g13_pending_dispatch_complete(item &G13PendingSubmission) bool {
	for index := u32(0); index < item.command_count; index++ {
		if item.commands[index].compute_job != unsafe { nil }
			|| item.commands[index].render_job != unsafe { nil } { return false }
	}
	return true
}

// Only one poller consumes nodes. Detach a snapshot, then put retained older
// nodes before concurrent appends. Each node pins its queue through the poll.
// Only unpublished work blocks a later batch on that queue.
fn process_pending_submissions() {
	pending_lock.acquire()
	if pending_poll_active {
		// A replacement worker can reach its final poll while the current
		// snapshot is detached and misses its newly queued work.
		pending_poll_requested = true
		pending_lock.release()
		return
	}
	if pending_head == unsafe { nil } {
		pending_lock.release()
		return
	}
	pending_poll_active = true
	for {
		current := pending_head
		pending_head = unsafe { nil }
		pending_tail = unsafe { nil }
		pending_count = 0
		pending_poll_requested = false
		pending_lock.release()
		poll_pending_batch(current)
		if !pending_poll_requested {
			pending_poll_active = false
			pending_lock.release()
			return
		}
	}
}

// The active poller owns this snapshot. Return holding pending_lock so the
// handoff test is atomic with restoring the retained list.
fn poll_pending_batch(first &G13PendingSubmission) {
	mut current := unsafe { first }
	// Clear the queue-local scratch for every queue in this snapshot before
	// visiting any of them. Concurrent appends join the next snapshot.
	mut cursor := current
	for cursor != unsafe { nil } {
		mut queue := unsafe { cursor.queue }
		queue.dispatch_blocked_in_poll = false
		cursor = cursor.next
	}
	mut retained_head := &G13PendingSubmission(unsafe { nil })
	mut retained_tail := &G13PendingSubmission(unsafe { nil })
	mut retained_count := u64(0)
	for current != unsafe { nil } {
		mut item := unsafe { current }
		current = item.next
		item.next = unsafe { nil }
		mut queue := unsafe { item.queue }
		earlier := queue.dispatch_blocked_in_poll
		if earlier || poll_g13_pending(mut item) {
			release_completed_g13_timestamps(item)
			if !g13_pending_dispatch_complete(item) { queue.dispatch_blocked_in_poll = true }
			if retained_tail == unsafe { nil } {
				retained_head = item
			} else {
				retained_tail.next = item
			}
			retained_tail = item
			retained_count++
		} else {
			for index := u32(0); index < item.command_count; index++ {
				assert item.commands[index].compute_job == unsafe { nil }
				assert item.commands[index].render_job == unsafe { nil }
			}
			assert katomic.load(&item.callbacks_remaining) == 0
			signal_g13_submission_fence(item.final_fence, int(katomic.load(&item.failure)))
			if item.operation_active {
				mut manager := unsafe { item.manager }
				// Its commands all completed on the GPU: Asahi's agx_stats job count.
				manager.note_g13_job()
				manager.finish_g13_submission_operation()
			}
			// GPU callbacks have dropped their final node access. Release global
			// timestamp mappings outside manager.lock, while file/VM pins remain.
			mut owner := unsafe { item.file }
			owner.release_g13_submission_timestamps(item.timestamps)
			submission.release_sync_array(item.dependencies)
			queue.release_file_reference()
			katomic.dec(mut &item.vm.inflight)
			memory.free(voidptr(item))
		}
	}
	pending_lock.acquire()
	if retained_tail != unsafe { nil } {
		retained_tail.next = pending_head
		pending_head = retained_head
		if pending_tail == unsafe { nil } { pending_tail = retained_tail }
		pending_count += retained_count
	}
}

pub fn service_file_work() {
	process_pending_submissions()
	reap_open_detached_g13_queues()
	reap_closed_files()
}
