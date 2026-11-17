// SPDX-License-Identifier: GPL-2.0-or-later
module syncobj

import event
import event.eventstruct

// A descriptor owns this node and its event until cancel_fence_event returns.
// The immutable fence argument supplies the lock even after signaling detaches
// the node. No callback can access the owner after cancellation unlocks.
pub struct FenceEvent {
mut:
	fence &DmaFence = unsafe { nil }
	next &FenceEvent = unsafe { nil }
	event &eventstruct.Event = unsafe { nil }
}

// Register once while checking readiness under the completion lock. Repeated
// polls of the same descriptor share its embedded node and resource event.
pub fn poll_fence(fence &DmaFence, node &FenceEvent, target &eventstruct.Event) bool {
	if fence == unsafe { nil } || node == unsafe { nil } || target == unsafe { nil } { return false }
	if is_signaled(fence) { return true }
	enable_array(fence)
	drain_chain_notifications()
	mut f := unsafe { fence }
	mut n := unsafe { node }
	f.lock.acquire()
	defer { f.lock.release() }
	if f.signaled { return true }
	if n.fence == unsafe { nil } {
		n.fence = unsafe { fence }
		n.event = unsafe { target }
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
	n.fence = unsafe { nil }; n.next = unsafe { nil }; n.event = unsafe { nil }
}

// Caller holds the fence lock until every wake completes. Final close must
// acquire the same lock before freeing a descriptor's embedded node/event.
fn (mut f DmaFence) notify_events_locked() {
	for f.poll_events != unsafe { nil } {
		mut node := unsafe { f.poll_events }
		f.poll_events = unsafe { node.next }
		mut target := unsafe { node.event }
		node.fence = unsafe { nil }; node.next = unsafe { nil }; node.event = unsafe { nil }
		event.trigger(mut target, false)
	}
}
