// SPDX-License-Identifier: GPL-2.0-or-later
module syncobj

import event
import event.eventstruct
import katomic

// A descriptor owns this node and its event until cancel_fence_event returns.
// The immutable fence argument supplies the lock even after signaling detaches
// the node. No callback can access the owner after cancellation unlocks.
pub struct FenceEvent {
mut:
	fence &DmaFence = unsafe { nil }
	next &FenceEvent = unsafe { nil }
	event &eventstruct.Event = unsafe { nil }
	generation &u64 = unsafe { nil }
}

// Register once while checking readiness under the completion lock. Repeated
// polls of the same descriptor share its embedded node and resource event.
pub fn poll_fence(fence &DmaFence, node &FenceEvent, target &eventstruct.Event) bool {
	if fence == unsafe { nil } || node == unsafe { nil } || target == unsafe { nil } { return false }
	if is_signaled(fence) { return true }
	enable_array(fence)
	drain_chain_notifications()
	return poll_leaf_event(fence, node, target, unsafe { nil })
}

// PRIME supplies a published leaf and an optional direction generation. This
// path does no array activation or notification draining under the GEM lock.
pub fn poll_leaf_event(fence &DmaFence, node &FenceEvent, target &eventstruct.Event, generation &u64) bool {
	mut f := unsafe { fence }
	mut n := unsafe { node }
	f.lock.acquire()
	defer { f.lock.release() }
	if f.signaled { return true }
	if n.fence == unsafe { nil } {
		n.fence = unsafe { fence }
		n.event = unsafe { target }
		n.generation = unsafe { generation }
		n.next = unsafe { f.poll_events }
		f.poll_events = unsafe { node }
	}
	return false
}

// Final descriptor release synchronizes with both registration and completion.
// Unlinking a borrowed node never retires the retained fence itself.
pub fn cancel_fence_event(fence &DmaFence, node &FenceEvent) {
	if fence == unsafe { nil } || node == unsafe { nil } { return }
	mut f := unsafe { fence }
	mut n := unsafe { node }
	f.lock.acquire()
	defer { f.lock.release() }
	if voidptr(n.fence) != voidptr(fence) { return }
	mut previous := &FenceEvent(unsafe { nil })
	mut cursor := unsafe { f.poll_events }
	for cursor != unsafe { nil } {
		if voidptr(cursor) == voidptr(node) {
			if previous == unsafe { nil } { f.poll_events = unsafe { cursor.next } }
			else { unsafe { previous.next = cursor.next } }
			break
		}
		previous = unsafe { cursor }
		cursor = unsafe { cursor.next }
	}
	n.fence = unsafe { nil }; n.next = unsafe { nil }; n.event = unsafe { nil }; n.generation = unsafe { nil }
}

// Caller holds the fence lock until every wake completes. Final close must
// acquire the same lock before freeing a descriptor's embedded node/event.
fn (mut f DmaFence) notify_events_locked() {
	for f.poll_events != unsafe { nil } {
		mut node := unsafe { f.poll_events }
		f.poll_events = unsafe { node.next }
		mut target := unsafe { node.event }
		mut generation := unsafe { node.generation }
		node.fence = unsafe { nil }; node.next = unsafe { nil }; node.event = unsafe { nil }
		node.generation = unsafe { nil }
		directional := generation != unsafe { nil }
		if directional { katomic.inc(mut generation) }
		event.trigger(mut target, directional)
	}
}
