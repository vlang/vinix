// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module file

import drm.syncobj
import drm.ioctl
import gpu.agx.gpu
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
	error       int
}

struct G13PendingSubmission {
mut:
	next                &G13PendingSubmission = unsafe { nil }
	file                &GpuFile              = unsafe { nil }
	vm_id               u32
	queue               &gpu.G13QueueResources = unsafe { nil }
	manager             &gpu.GpuManager        = unsafe { nil }
	dependencies        submission.SyncArray
	dependencies_ready  bool
	initial_barriers    u32 // explicit index-zero dependencies, by subqueue
	initial_events      gpu.G13InitialEvents
	final_fence         &syncobj.DmaFence = unsafe { nil }
	commands            [64]G13PendingCommand
	command_count       u32
	callbacks_remaining u32
	failure             int
}

__global pending_lock klock.Lock
__global pending_head &G13PendingSubmission = unsafe { nil }
__global pending_tail &G13PendingSubmission = unsafe { nil }
__global pending_count = u64(0)
__global pending_poll_active = false

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
				item.initial_barriers |= u32(1) << pipe
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
			if failure != 0 { return failure }
		}
	}
	return 0
}

// All source metadata remains caller-owned until this node is queued. The
// manager reads and pins its event slots while holding its publication lock.
fn install_g13_batch_barriers(mut item G13PendingSubmission) bool {
	mut manager := unsafe { item.manager }
	for index := u32(0); index < item.command_count; index++ {
		command := &item.commands[index]
		mut sources := [2]gpu.G13BarrierSource{}
		for pipe in 0 .. 2 {
			dependency := command.wait_for[pipe]
			if dependency == 0 {
				if command.initial_barriers & (u32(1) << pipe) != 0 {
					sources[pipe] = gpu.G13BarrierSource{ initial: item.initial_events.values[pipe] }
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

fn register_g13_pending(mut manager gpu.GpuManager, item &G13PendingSubmission) bool {
	mut jobs := [64]gpu.G13SubmissionJob{}
	for index := u32(0); index < item.command_count; index++ {
		jobs[index] = gpu.G13SubmissionJob{ render: item.commands[index].render_job, compute: item.commands[index].compute_job }
	}
	return manager.queue_g13_submission(jobs, item.command_count, enqueue_g13_pending, voidptr(item))
}

// Called under manager.lock while the ioctl still holds file.lock.
fn enqueue_g13_pending(data voidptr) {
	mut item := unsafe { &G13PendingSubmission(data) }
	assert item.next == unsafe { nil }
	pending_lock.acquire()
	if pending_tail == unsafe { nil } { pending_head = item } else { pending_tail.next = item }
	pending_tail = item
	pending_count++
	pending_lock.release()
}

// DRM scheduler dependencies order execution. A signaled input fence releases
// its wait even when it carries an error; only this submission's own work sets
// its completion error. The queue's own native fences are elided, as in its
// DRM scheduler entity; every other input still waits for actual signaling.
fn g13_dependencies_ready(dependencies &submission.SyncArray, queue_context u64) bool {
	for index := u32(0); index < dependencies.count; index++ {
		if !syncobj.queue_dependency_ready(dependencies.fences[index], queue_context) { return false }
	}
	return true
}

fn cancel_g13_pending(mut item G13PendingSubmission, failure int) {
	if katomic.load(&item.failure) == 0 { katomic.store(mut &item.failure, failure) }
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

// Explicit dependencies wait only for producer publication. Their installed
// firmware prefixes wait for execution; CPU callback/reaper order must not
// serialize GPU work. Unpublished producers still block dependent subqueues.
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
			katomic.load(&item.failure)
		})
		return katomic.load(&item.callbacks_remaining) != 0
	}
	mut blocked := [2]bool{}
	for index := u32(0); index < item.command_count; index++ {
		// Shutdown can deliver callbacks for prepared jobs while their metadata
		// is still caller-owned. Drop those pointers before retiring this node.
		if manager.state != .running {
			cancel_g13_pending(mut item, -19)
			return katomic.load(&item.callbacks_remaining) != 0
		}
		mut command := &item.commands[index]
		if katomic.load(&command.done) || command.published { continue }
		if blocked[command.pipe] { continue }
		for dependency in command.wait_for {
			if dependency == 0 { continue }
			prior := &item.commands[dependency - 1]
			if !prior.published {
				blocked[command.pipe] = true
				continue
			}
			dependency_error := if katomic.load(&prior.done) { katomic.load(&prior.error) } else { 0 }
			if dependency_error != 0 {
				cancel_g13_pending(mut item, dependency_error)
				return katomic.load(&item.callbacks_remaining) != 0
			}
		}
		if blocked[command.pipe] { continue }
		completed_error := g13_pending_error(item)
		if completed_error != 0 {
			cancel_g13_pending(mut item, completed_error)
			return katomic.load(&item.callbacks_remaining) != 0
		}
		if manager.g13_queue_dispatch_blocked(item.queue) { return true }
		if command.compute_job != unsafe { nil } {
			if manager.submit_g13_compute_job(command.compute_job) {
				// The manager can free transferred metadata before returning.
				command.compute_job = unsafe { nil }
				command.published = true
			}
		} else if command.render_job != unsafe { nil } {
			if manager.submit_g13_render_job(command.render_job) {
				command.render_job = unsafe { nil }
				command.published = true
			}
		}
		if !command.published { blocked[command.pipe] = true }
	}
	if katomic.load(&item.callbacks_remaining) != 0 { return true }
	// Acquiring zero callbacks observes shutdown's preceding state write.
	// Check afterward: stop may have run during the last publication or just
	// before this count load, leaving caller-owned prepared metadata behind.
	if manager.state != .running { cancel_g13_pending(mut item, -19) }
	// The last callback can run during publication. Read its error only after
	// acquiring the zero callback count, before allowing aggregate notification.
	final_error := g13_pending_error(item)
	if final_error != 0 { katomic.store(mut &item.failure, final_error) }
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

// Only the GPU worker consumes nodes. Detach a bounded snapshot, then put
// retained older nodes BEFORE concurrent appends. Remember both outstanding
// retirement and unpublished work per queue; only the latter blocks an
// independent later batch. No pointer to an older node survives this poll.
fn process_pending_submissions() {
	pending_lock.acquire()
	if pending_poll_active || pending_head == unsafe { nil } {
		pending_lock.release()
		return
	}
	pending_poll_active = true
	mut current := pending_head
	pending_head = unsafe { nil }
	pending_tail = unsafe { nil }
	pending_count = 0
	pending_lock.release()
	mut retained_head := &G13PendingSubmission(unsafe { nil })
	mut retained_tail := &G13PendingSubmission(unsafe { nil })
	mut retained_count := u64(0)
	mut blocked := unsafe { [128]voidptr{} }
	mut unpublished := [128]bool{}
	mut blocked_count := u32(0)
	for current != unsafe { nil } {
		mut item := unsafe { current }
		current = item.next
		item.next = unsafe { nil }
		mut gate := -1
		for index := u32(0); index < blocked_count; index++ {
			if blocked[index] == voidptr(item.queue) {
				gate = int(index)
				break
			}
		}
		earlier := if gate >= 0 { unpublished[gate] } else { blocked_count == 128 }
		if earlier || poll_g13_pending(mut item) {
			if gate < 0 && blocked_count < 128 {
				gate = int(blocked_count)
				blocked[blocked_count] = voidptr(item.queue)
				blocked_count++
			}
			if gate >= 0 && !g13_pending_dispatch_complete(item) { unpublished[gate] = true }
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
			signal_g13_submission_fence(item.final_fence, katomic.load(&item.failure))
			katomic.dec(mut &item.file.inflight_by_vm[item.vm_id])
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
	pending_poll_active = false
	pending_lock.release()
}

pub fn service_file_work() {
	process_pending_submissions()
	reap_closed_files()
}
