// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module syncobj

import katomic
import klock
import memory

// Embedded in the retained parent, linked under its child's completion lock.
// Neither registering nor propagating completion allocates storage.
struct ChainWaiter {
mut:
	parent &DmaFence = unsafe { nil }
	next &ChainWaiter = unsafe { nil }
}

__global (
	chain_notify_lock klock.Lock
	chain_notify_head &DmaFence = unsafe { nil }
	chain_notify_tail &DmaFence = unsafe { nil }
	chain_notify_draining bool
)

// Reserve before publication. Only an unpublished reservation may be freed;
// published chains retain the existing native fence-metadata lifetime.
pub fn reserve_chain() ?&DmaFence {
	context := new_queue_context() or { return none }
	storage := memory.malloc_packed_fallible(sizeof(DmaFence))
	if storage == unsafe { nil } { return none }
	mut fence := unsafe { &DmaFence(storage) }
	unsafe { *fence = DmaFence{ chain_reserved: true, chain_context: context } }
	return fence
}

pub fn release_chain_reservation(fence &DmaFence) {
	if fence != unsafe { nil } && fence.chain_reserved { memory.free(voidptr(fence)) }
}

fn register_chain_waiter(child &DmaFence, node &ChainWaiter, parent &DmaFence) {
	if child == unsafe { nil } { return }
	enable_array(child)
	mut f := unsafe { child }
	mut n := unsafe { node }
	f.lock.acquire()
	if !f.signaled {
		n.parent = unsafe { parent }
		n.next = unsafe { f.chain_waiters }
		f.chain_waiters = unsafe { node }
	}
	f.lock.release()
}

// Caller owns the fresh reservation and serializes publication. Immutable
// links are fully initialized before any child can queue this retained parent.
fn initialize_chain(node &DmaFence, previous &DmaFence, payload &DmaFence, point u64) {
	mut f := unsafe { node }
	f.chain = true
	f.chain_prev = unsafe { previous }
	f.chain_payload = unsafe { payload }
	if previous != unsafe { nil } && previous.chain {
		if point > previous.seqno {
			f.chain_context = previous.chain_context
			f.chain_prev_seqno = previous.seqno
			f.seqno = point
		} else {
			f.seqno = previous.seqno
		}
	} else { f.seqno = point }
	f.context = f.chain_context
	// The reservation is now retained even if completion races publication.
	f.chain_reserved = false
	if payload.merge_reserved { unsafe { payload.merge_reserved = false } }
	register_chain_waiter(previous, unsafe { &f.chain_previous_waiter }, node)
	register_chain_waiter(payload, unsafe { &f.chain_payload_waiter }, node)
	// Close the registration/completion race without running the global
	// drainer under the sync object's publication lock.
	if chain_prefix_ready(node) { complete_fence(node, 0, true) }
}

// Linux drm_syncobj_add_point semantics, including zero, repeated and
// decreasing points. A sync-file import may contain another retained chain.
// The completion queue propagates through it without recursive evaluation.
pub fn add_chain_point(obj &SyncObj, reservation &DmaFence, payload &DmaFence, point u64) bool {
	if obj == unsafe { nil } || reservation == unsafe { nil }
		|| !reservation.chain_reserved || payload == unsafe { nil }
		|| payload.chain_reserved { return false }
	mut o := unsafe { obj }
	o.lock.acquire()
	initialize_chain(reservation, o.fence, payload, point)
	o.fence = unsafe { reservation }
	o.timeline_points.clear()
	o.publish_captures_locked(reservation)
	o.publish_timeline_captures_locked(reservation)
	o.publish_eventfds_locked()
	o.lock.release()
	drain_chain_notifications()
	return true
}

// Immutable-link equivalent of dma_fence_chain_walk: skip retired contained
// leaves, not just containers whose entire earlier prefix has completed.
pub fn chain_previous(fence &DmaFence) &DmaFence {
	if fence == unsafe { nil } || !fence.chain { return unsafe { nil } }
	mut cursor := unsafe { fence.chain_prev }
	for cursor != unsafe { nil } {
		if cursor.chain {
			if !array_leaf_ready(cursor.chain_payload) { break }
			cursor = unsafe { cursor.chain_prev }
		} else {
			if array_leaf_ready(cursor) { cursor = unsafe { nil } }
			break
		}
	}
	return cursor
}

pub fn chain_contained(fence &DmaFence) &DmaFence {
	if fence == unsafe { nil } { return unsafe { nil } }
	return if fence.chain { unsafe { fence.chain_payload } } else { unsafe { fence } }
}

// Some(nil) is a valid already-completed prefix. None means no submitted
// fence or a point beyond the head. Point zero preserves the head snapshot.
pub fn get_chain_fence(obj &SyncObj, point u64) ?&DmaFence {
	fence := get_fence(obj) or { return none }
	return find_chain_fence(fence, point)
}

// Resolve an already captured head without taking the object's lock again.
// Some(nil) is an available retired prefix; None is not yet submitted.
fn find_chain_fence(fence &DmaFence, point u64) ?&DmaFence {
	if fence == unsafe { nil } { return none }
	if point == 0 { return fence }
	if !fence.chain || fence.seqno < point { return none }
	mut cursor := unsafe { fence }
	for cursor != unsafe { nil } {
		if !cursor.chain || cursor.chain_context != fence.chain_context || cursor.chain_prev_seqno < point { break }
		cursor = chain_previous(cursor)
	}
	return cursor
}

// drm_syncobj_query_ioctl reports either the head's submitted sequence or
// completed progress in that head's context. An unordered context boundary
// stops the search. Empty objects and binary fences always report zero.
pub fn query_timeline_point(obj &SyncObj, last_submitted bool) u64 {
	fence := get_fence(obj) or { return 0 }
	if !fence.chain { return 0 }
	if last_submitted { return fence.seqno }
	mut last := unsafe { fence }
	mut cursor := unsafe { fence }
	for cursor != unsafe { nil } {
		if !cursor.chain || cursor.chain_context != fence.chain_context { break }
		last = unsafe { cursor }
		cursor = chain_previous(cursor)
	}
	return if is_signaled(last) { last.seqno } else { last.chain_prev_seqno }
}

fn chain_prefix_ready(fence &DmaFence) bool {
	mut cursor := unsafe { fence }
	for cursor != unsafe { nil } {
		if katomic.load(&cursor.signaled) { return true }
		if !cursor.chain { return array_leaf_ready(cursor) }
		if !array_leaf_ready(cursor.chain_payload) { return false }
		cursor = unsafe { cursor.chain_prev }
	}
	return true
}

fn enqueue_chain(parent &DmaFence) {
	chain_notify_lock.acquire()
	enqueue_chain_locked(parent)
	chain_notify_lock.release()
}

fn enqueue_chain_locked(parent &DmaFence) {
	mut f := unsafe { parent }
	if !f.chain_notify_queued {
		if f.array_snapshot { katomic.inc(mut &f.array_snapshot_refs) }
		f.chain_notify_queued = true
		f.chain_notify_next = unsafe { nil }
		if chain_notify_tail == unsafe { nil } { chain_notify_head = unsafe { parent } }
		else { unsafe { chain_notify_tail.chain_notify_next = parent } }
		chain_notify_tail = unsafe { parent }
	}
}

fn (mut f DmaFence) notify_chains_locked() {
	for f.chain_waiters != unsafe { nil } {
		mut node := unsafe { f.chain_waiters }
		f.chain_waiters = unsafe { node.next }
		node.next = unsafe { nil }
		if node.parent.fence_array { array_child_complete(node.parent, f.error) }
		else { enqueue_chain(node.parent) }
	}
}

fn drain_chain_notifications() {
	chain_notify_lock.acquire()
	if chain_notify_draining { chain_notify_lock.release(); return }
	chain_notify_draining = true
	for chain_notify_head != unsafe { nil } {
		mut f := unsafe { chain_notify_head }
		chain_notify_head = unsafe { f.chain_notify_next }
		if chain_notify_head == unsafe { nil } { chain_notify_tail = unsafe { nil } }
		f.chain_notify_next = unsafe { nil }
		f.chain_notify_queued = false
		forward := f.deadline_forward
		deadline := f.deadline_ns
		f.deadline_forward = false
		chain_notify_lock.release()
		if forward { forward_deadline(f, deadline) }
		// Completion of the previous root enqueues us again if it is still
		// pending. No recursive walk or callback is needed on this path.
		if f.fence_array { if array_ready(f) { complete_array(f) } }
		else if (f.chain_prev == unsafe { nil } || katomic.load(&f.chain_prev.signaled))
			&& katomic.load(&f.chain_payload.signaled) { complete_fence(f, 0, true) }
		if f.array_snapshot { release_snapshot_reference(f) }
		chain_notify_lock.acquire()
	}
	chain_notify_draining = false
	chain_notify_lock.release()
}
