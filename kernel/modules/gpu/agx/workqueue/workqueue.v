@[has_globals]
module workqueue

// GPU work queue management
// Manages submission and completion of GPU work items through ring buffers.
// Each queue has 127 job slots. Work errors track timeout, fault, killed,
// and channel error conditions. Translates workqueue.rs from the Asahi
// Linux GPU driver.

import drm.syncobj
import klock

pub const max_job_slots = 127

// Work error codes
pub const work_err_none = u32(0)
pub const work_err_timeout = u32(1)
pub const work_err_fault = u32(2)
pub const work_err_killed = u32(3)
pub const work_err_channel_error = u32(4)

pub struct WorkItem {
pub mut:
	slot        u32
	cmd_type    u32 // vertex=0, fragment=1, compute=2
	stamp_value u32
	fence       &syncobj.DmaFence = unsafe { nil }
	submitted   bool
	completed   bool
	error       u32
	timeout_ns  u64
}

pub struct WorkQueue {
pub mut:
	id             u32
	vm_id          u32
	priority       u32
	caps           u32
	slots          [max_job_slots]&WorkItem
	next_slot      u32
	completed_slot u32
	pending_count  u32
	lock           klock.Lock
}

// Create host-side completion bookkeeping. Firmware-visible queue state is
// generation-specific and owned by gpu.G13QueueResources/G17QueueResources.
pub fn new_workqueue(id u32, vm_id u32, priority u32, caps u32) ?&WorkQueue {
	if id == 0 || caps == 0 || priority >= 4 {
		return none
	}

	return &WorkQueue{
		id:       id
		vm_id:    vm_id
		priority: priority
		caps:     caps
	}
}

// Submit a work item to the queue. Returns the slot index on success,
// or none if the queue is full.
pub fn (mut wq WorkQueue) submit(item &WorkItem) ?u32 {
	wq.lock.acquire()
	defer {
		wq.lock.release()
	}

	slot := wq.get_next_slot_locked() or {
		return none
	}

	mut w := unsafe { item }
	w.slot = slot
	w.submitted = true
	w.completed = false
	w.error = work_err_none

	wq.slots[slot] = unsafe { item }
	wq.pending_count++
	wq.next_slot = (slot + 1) % max_job_slots

	return slot
}

// Mark a job as complete and signal its associated fence.
pub fn (mut wq WorkQueue) complete(slot u32, error u32) {
	if slot >= max_job_slots {
		return
	}

	wq.lock.acquire()
	defer {
		wq.lock.release()
	}

	item_opt := wq.slots[slot]
	if item_opt == unsafe { nil } {
		return
	}
	mut item := unsafe { item_opt }
	item.completed = true
	item.error = error

	// Signal the DMA fence if one is attached
	if item.fence != unsafe { nil } {
		if error == work_err_none {
			syncobj.signal(item.fence)
		} else {
			syncobj.signal_error(item.fence, -int(error))
		}
	}

	if wq.pending_count > 0 {
		wq.pending_count--
	}
	wq.completed_slot = slot

	// Free the slot
	wq.slots[slot] = unsafe { nil }
}

// Find the next free slot in the work queue. Caller must hold the lock.
fn (wq &WorkQueue) get_next_slot_locked() ?u32 {
	for i := u32(0); i < max_job_slots; i++ {
		idx := (wq.next_slot + i) % max_job_slots
		if wq.slots[idx] == unsafe { nil } {
			return idx
		}
	}
	return none
}

// Find the next free slot in the work queue (public, acquires lock).
pub fn (mut wq WorkQueue) get_next_slot() ?u32 {
	wq.lock.acquire()
	defer {
		wq.lock.release()
	}

	return wq.get_next_slot_locked()
}

// Check whether the work queue has no pending work items.
pub fn (wq &WorkQueue) is_empty() bool {
	return wq.pending_count == 0
}

// Return the number of pending (submitted but not completed) work items.
pub fn (wq &WorkQueue) pending() u32 {
	return wq.pending_count
}

// Destroy the work queue and free its ring buffer.
pub fn (mut wq WorkQueue) destroy() {
	wq.lock.acquire()
	defer {
		wq.lock.release()
	}

	// Signal any remaining fences with an error
	for i := u32(0); i < max_job_slots; i++ {
		item_opt := wq.slots[i]
		if item_opt == unsafe { nil } {
			continue
		}
		item := unsafe { item_opt }
		if item.fence != unsafe { nil } && !item.completed {
			// Queue destruction cancels work; wake waiters with a failure rather
			// than falsely reporting successful GPU completion.
			syncobj.signal_error(item.fence, -int(work_err_killed))
		}
		wq.slots[i] = unsafe { nil }
	}

	wq.pending_count = 0

}
