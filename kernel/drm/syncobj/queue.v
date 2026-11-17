// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module syncobj

import klock

struct QueueFenceContexts {
mut:
	next u64 = 1
}

// Zero means exhausted or untrusted. Never wrap or recycle a queue's identity,
// including after device reset, failed queue construction or handle reuse.
fn (mut contexts QueueFenceContexts) allocate() ?u64 {
	if contexts.next == 0 { return none }
	value := contexts.next
	contexts.next = if value == ~u64(0) { u64(0) } else { value + 1 }
	return value
}

__global queue_context_lock klock.Lock
__global queue_contexts = QueueFenceContexts{}

pub fn new_queue_context() ?u64 {
	queue_context_lock.acquire()
	defer { queue_context_lock.release() }
	return queue_contexts.allocate()
}

pub fn new_queue_fence(context u64, seqno u64, queue_context u64) &DmaFence {
	return &DmaFence{ context: if queue_context != 0 { queue_context } else { context }, seqno: seqno, queue_context: queue_context }
}

// Asahi has one DRM scheduler/entity per user queue. Its own fences do not
// gate that entity; publication FIFO and explicit firmware dependencies order
// its jobs. Other queues and generic fences still wait for actual signaling.
pub fn queue_dependency_ready(fence &DmaFence, queue_context u64) bool {
	if fence == unsafe { nil } { return true }
	if queue_context != 0 && fence.queue_context == queue_context { return true }
	return is_signaled(fence)
}
