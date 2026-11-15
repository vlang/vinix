// SPDX-License-Identifier: GPL-2.0-or-later
module syncobj

// A synchronous caller lends this node until release_capture returns. The
// object lock protects the list and captured fence. Native syncobj/fence
// metadata is retained, so object destruction never invalidates this borrow.
pub struct FenceCapture {
mut:
	object &SyncObj = unsafe { nil }
	next &FenceCapture = unsafe { nil }
	fence &DmaFence = unsafe { nil }
	pending bool
}

// Register a fresh node while taking the initial snapshot under the same
// lock used by replacement. A missing fence without WAIT_FOR_SUBMIT is invalid.
pub fn prepare_capture(obj &SyncObj, capture &FenceCapture, wait_for_submit bool) bool {
	if obj == unsafe { nil } || capture == unsafe { nil } { return false }
	mut o := unsafe { obj }
	mut c := unsafe { capture }
	if c.object != unsafe { nil } { return false }
	o.lock.acquire()
	c.object = unsafe { obj }
	c.fence = unsafe { o.fence }
	if c.fence == unsafe { nil } && wait_for_submit {
		c.next = unsafe { o.pending_captures }
		c.pending = true
		o.pending_captures = unsafe { capture }
	}
	valid := c.fence != unsafe { nil } || wait_for_submit
	o.lock.release()
	return valid
}

pub fn captured_fence(capture &FenceCapture) ?&DmaFence {
	if capture == unsafe { nil } || capture.object == unsafe { nil } { return none }
	mut o := unsafe { capture.object }
	o.lock.acquire()
	defer { o.lock.release() }
	if capture.fence == unsafe { nil } { return none }
	return unsafe { capture.fence }
}

// Called with the object lock held. Detaching every node before unlocking
// makes its first non-null fence final, even across immediate replacement.
fn (mut obj SyncObj) publish_captures_locked(fence &DmaFence) {
	if fence == unsafe { nil } { return }
	mut cursor := unsafe { obj.pending_captures }
	obj.pending_captures = unsafe { nil }
	for cursor != unsafe { nil } {
		next := unsafe { cursor.next }
		cursor.fence = unsafe { fence }
		cursor.next = unsafe { nil }
		cursor.pending = false
		cursor = unsafe { next }
	}
}

// Unlink before the caller's stack storage can disappear, on every exit.
// A concurrent producer finishes touching this node under this same lock.
pub fn release_capture(capture &FenceCapture) {
	if capture == unsafe { nil } || capture.object == unsafe { nil } { return }
	mut o := unsafe { capture.object }
	mut c := unsafe { capture }
	o.lock.acquire()
	if c.pending {
		mut previous := &FenceCapture(unsafe { nil })
		mut cursor := unsafe { o.pending_captures }
		for cursor != unsafe { nil } {
			if voidptr(cursor) == voidptr(capture) {
				if previous == unsafe { nil } { o.pending_captures = unsafe { cursor.next } }
				else { previous.next = unsafe { cursor.next } }
				break
			}
			previous = unsafe { cursor }
			cursor = unsafe { cursor.next }
		}
	}
	c.object = unsafe { nil }
	c.next = unsafe { nil }
	c.fence = unsafe { nil }
	c.pending = false
	o.lock.release()
}
