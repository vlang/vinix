// SPDX-License-Identifier: GPL-2.0-or-later
module syncobj

// Synchronous timeline waits lend these nodes until release returns. The
// object lock protects capture and membership. Captured metadata is retained;
// available=true with a nil fence represents an already-completed prefix.
pub struct TimelineCapture {
mut:
	object &SyncObj = unsafe { nil }
	next &TimelineCapture = unsafe { nil }
	fence &DmaFence = unsafe { nil }
	point u64
	available bool
	pending bool
}

fn (mut capture TimelineCapture) resolve_locked(head &DmaFence) bool {
	fence := find_chain_fence(head, capture.point) or { return false }
	capture.fence = unsafe { fence }
	capture.available = true
	return true
}

// Initial validation takes a snapshot only. Linux checks every initial fence
// before arming submission callbacks, so transient publication before arm must
// not be captured by an eagerly registered node.
pub fn prepare_timeline_capture(obj &SyncObj, capture &TimelineCapture, point u64, allow_future bool) bool {
	if obj == unsafe { nil } || capture == unsafe { nil } || capture.object != unsafe { nil } { return false }
	mut o := unsafe { obj }
	mut c := unsafe { capture }
	o.lock.acquire()
	c.object = unsafe { obj }
	c.point = point
	valid := c.resolve_locked(o.fence) || allow_future
	o.lock.release()
	return valid
}

// Recheck under the same lock used for publication, then lend the unresolved
// node. Once captured, replacement/reset cannot change this wait's fence.
pub fn arm_timeline_capture(capture &TimelineCapture) {
	if capture == unsafe { nil } || capture.object == unsafe { nil } { return }
	mut o := unsafe { capture.object }
	mut c := unsafe { capture }
	o.lock.acquire()
	if !c.available && !c.pending && !c.resolve_locked(o.fence) {
		c.next = unsafe { o.timeline_captures }
		c.pending = true
		o.timeline_captures = unsafe { capture }
	}
	o.lock.release()
}

pub fn captured_timeline_fence(capture &TimelineCapture) ?&DmaFence {
	if capture == unsafe { nil } || capture.object == unsafe { nil } { return none }
	mut o := unsafe { capture.object }
	o.lock.acquire()
	defer { o.lock.release() }
	if !capture.available { return none }
	return unsafe { capture.fence }
}

// Caller holds the object lock. The lookup reads immutable links and atomic
// leaf completion bits, without taking a fence lock or invoking callbacks.
fn (mut obj SyncObj) publish_timeline_captures_locked(head &DmaFence) {
	if head == unsafe { nil } { return }
	mut previous := &TimelineCapture(unsafe { nil })
	mut cursor := unsafe { obj.timeline_captures }
	for cursor != unsafe { nil } {
		next := unsafe { cursor.next }
		if cursor.resolve_locked(head) {
			if previous == unsafe { nil } { obj.timeline_captures = unsafe { next } }
			else { unsafe { previous.next = next } }
			cursor.next = unsafe { nil }
			cursor.pending = false
		} else { previous = unsafe { cursor } }
		cursor = unsafe { next }
	}
}

// Unlink on every exit before the syscall frees this node's storage. A racing
// producer completes its final access under the same retained object's lock.
pub fn release_timeline_capture(capture &TimelineCapture) {
	if capture == unsafe { nil } || capture.object == unsafe { nil } { return }
	mut o := unsafe { capture.object }
	mut c := unsafe { capture }
	o.lock.acquire()
	if c.pending {
		mut previous := &TimelineCapture(unsafe { nil })
		mut cursor := unsafe { o.timeline_captures }
		for cursor != unsafe { nil } {
			if voidptr(cursor) == voidptr(capture) {
				if previous == unsafe { nil } { o.timeline_captures = unsafe { cursor.next } }
				else { unsafe { previous.next = cursor.next } }
				break
			}
			previous = unsafe { cursor }
			cursor = unsafe { cursor.next }
		}
	}
	c.object = unsafe { nil }; c.next = unsafe { nil }; c.fence = unsafe { nil }
	c.point = 0; c.available = false; c.pending = false
	o.lock.release()
}
