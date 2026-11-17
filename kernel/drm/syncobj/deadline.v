// SPDX-License-Identifier: GPL-2.0-or-later
module syncobj

import katomic

// Queue fences represent the scheduler's finished fence. Generic leaves and
// private stubs have no deadline operation. Containers forward to their
// children and remember the minimum to visit shared graphs once per hint.
fn record_deadline(fence &DmaFence, deadline i64) bool {
	if fence == unsafe { nil } || (!fence.chain && !fence.fence_array && fence.queue_context == 0) {
		return false
	}
	mut f := unsafe { fence }
	chain_notify_lock.acquire()
	defer { chain_notify_lock.release() }
	if katomic.load(&f.signaled) || (f.deadline_valid && f.deadline_ns <= deadline) {
		return false
	}
	f.deadline_ns = deadline
	f.deadline_valid = true
	if f.chain || f.fence_array {
		f.deadline_forward = true
		enqueue_chain_locked(fence)
		return true
	}
	return false
}

// The drainer calls this without its lock held. Published edges are immutable.
// Nested chains or arrays can enqueue children without growing the stack.
fn forward_deadline(fence &DmaFence, deadline i64) {
	if fence.fence_array {
		for index := u32(0); index < fence.array_count; index++ {
			record_deadline(unsafe { fence.array_fences[index] }, deadline)
		}
	} else {
		record_deadline(fence.chain_payload, deadline)
		record_deadline(chain_previous(fence), deadline)
	}
}

pub fn set_deadline(fence &DmaFence, deadline i64) {
	if record_deadline(fence, deadline) {
		drain_chain_notifications()
	}
}
