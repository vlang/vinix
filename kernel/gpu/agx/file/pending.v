// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module file

import drm.syncobj
import gpu.agx.gpu
import gpu.agx.submission
import katomic
import klock
import memory

// Prepared jobs stay caller-owned until publication. Each callback retains
// this node through callbacks_remaining; one extra VM pin spans the whole
// submission, including gaps between compute and render callbacks.
struct G13PendingSubmission {
mut:
	next                &G13PendingSubmission = unsafe { nil }
	file                &GpuFile              = unsafe { nil }
	vm_id               u32
	queue               &gpu.G13QueueResources = unsafe { nil }
	manager             &gpu.GpuManager        = unsafe { nil }
	dependencies        submission.SyncArray
	dependencies_ready  bool
	compute_job         &gpu.G13ComputeJobResources = unsafe { nil }
	render_job          &gpu.G13RenderJobResources  = unsafe { nil }
	has_compute         bool
	compute_done        bool
	compute_error       int
	callbacks_remaining u32
	failure             int
}

__global pending_lock klock.Lock
__global pending_head &G13PendingSubmission = unsafe { nil }
__global pending_tail &G13PendingSubmission = unsafe { nil }
__global pending_count = u64(0)
__global pending_poll_active = false

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

fn g13_dependency_status(dependencies &submission.SyncArray) int {
	mut waiting := false
	for index := u32(0); index < dependencies.count; index++ {
		fence := dependencies.fences[index]
		if !syncobj.is_signaled(fence) {
			waiting = true
			continue
		}
		failure := syncobj.get_error(fence)
		if failure != 0 { return failure }
	}
	return if waiting { 1 } else { 0 }
}

fn cancel_g13_pending(mut item G13PendingSubmission, failure int) {
	if katomic.load(&item.failure) == 0 { katomic.store(mut &item.failure, failure) }
	mut manager := unsafe { item.manager }
	if item.compute_job != unsafe { nil } {
		job := item.compute_job
		item.compute_job = unsafe { nil }
		manager.release_g13_compute_job(job)
	}
	if item.render_job != unsafe { nil } {
		job := item.render_job
		item.render_job = unsafe { nil }
		manager.release_g13_render_job(job)
	}
}

// True retains the node for another poll. No fence or queue wait occurs on
// this path. In particular, a client signaling an output fence cannot make
// compute-to-render ordering or node retirement happen before a GPU callback.
fn poll_g13_pending(mut item G13PendingSubmission) bool {
	mut manager := unsafe { item.manager }
	if manager.state != .running {
		cancel_g13_pending(mut item, -19)
		return katomic.load(&item.callbacks_remaining) != 0
	}
	if !item.dependencies_ready {
		status := g13_dependency_status(&item.dependencies)
		if status == 1 { return true }
		if status != 0 {
			cancel_g13_pending(mut item, status)
			return katomic.load(&item.callbacks_remaining) != 0
		}
		item.dependencies_ready = true
	}
	if item.compute_job != unsafe { nil } {
		if manager.g13_queue_dispatch_blocked(item.queue) { return true }
		if manager.submit_g13_compute_job(item.compute_job) {
			// The manager may retire/free the job immediately after unlock.
			// Never read it again after this ownership transfer.
			item.compute_job = unsafe { nil }
		}
		return true
	}
	if item.render_job != unsafe { nil } {
		if item.has_compute {
			if !katomic.load(&item.compute_done) { return true }
			failure := katomic.load(&item.compute_error)
			if failure != 0 {
				cancel_g13_pending(mut item, failure)
				return katomic.load(&item.callbacks_remaining) != 0
			}
		}
		if manager.g13_queue_dispatch_blocked(item.queue) { return true }
		if manager.submit_g13_render_job(item.render_job) { item.render_job = unsafe { nil } }
		return true
	}
	return katomic.load(&item.callbacks_remaining) != 0
}

// Only the GPU worker consumes nodes. Detach a bounded snapshot, then put
// retained older nodes BEFORE concurrent appends. Requeueing at the tail
// would let a newer same-queue stamp overtake an older unpublished job.
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
	mut blocked_count := u32(0)
	for current != unsafe { nil } {
		mut item := unsafe { current }
		current = item.next
		item.next = unsafe { nil }
		mut earlier := blocked_count == 128
		for index := u32(0); index < blocked_count; index++ {
			if blocked[index] == voidptr(item.queue) {
				earlier = true
				break
			}
		}
		if earlier || poll_g13_pending(mut item) {
			if !earlier && blocked_count < 128 {
				blocked[blocked_count] = voidptr(item.queue)
				blocked_count++
			}
			if retained_tail == unsafe { nil } {
				retained_head = item
			} else {
				retained_tail.next = item
			}
			retained_tail = item
			retained_count++
		} else {
			assert item.compute_job == unsafe { nil } && item.render_job == unsafe { nil }
			assert katomic.load(&item.callbacks_remaining) == 0
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
