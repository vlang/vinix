@[has_globals]
module syncobj

// DRM sync objects and DMA fences for GPU synchronization.
// Fences represent points in a GPU command stream; sync objects
// wrap fences so user-space can wait on / signal them via ioctls.

import klock
import katomic
import memory
import sched
import time

pub struct FenceWaiter {
pub mut:
	callback  fn (&DmaFence) = unsafe { nil }
	triggered bool
}

pub struct DmaFence {
	// Kernel-only provenance, independent of the public context/seqno. A fence
	// retains only this scalar after its originating queue is destroyed.
	queue_context u64
pub mut:
	seqno    u64
	signaled bool
	error    int // 0 = success, negative = error code
	timestamp_ns u64 // first completion's monotonic timestamp
	context  u64
	lock     klock.Lock
	waiters  []&FenceWaiter
mut:
	private_stub bool
	poll_events &FenceEvent = unsafe { nil }
}

struct TimelinePoint {
	value u64
	fence &DmaFence = unsafe { nil }
}

// Handles name an object; imported handles share the same mutable object.
// The first entry is embedded. Imports own only separately allocated links.
struct SyncobjHandle {
mut:
	owner u64
	handle u32
	object &SyncObj = unsafe { nil }
	next &SyncobjHandle = unsafe { nil }
	allocated bool
}

pub struct SyncObj {
pub mut:
	// Creation's handle only; resolve imported names through lookup().
	handle u32
	fence  &DmaFence = unsafe { nil }
	lock   klock.Lock
mut:
	timeline_points []TimelinePoint
	pending_captures &FenceCapture = unsafe { nil }
	namespace SyncobjHandle
}

__global (
	syncobj_head &SyncobjHandle = unsafe { nil }
	syncobj_lock  klock.Lock
)

// Create a new DMA fence with the given context and sequence number.
pub fn new_fence(context u64, seqno u64) &DmaFence {
	return &DmaFence{
		seqno: seqno
		context: context
	}
}

// Signal a fence: mark it as signaled and invoke all registered waiters.
pub fn signal(fence &DmaFence) {
	if fence == unsafe { nil } {
		return
	}

	mut f := unsafe { fence }
	f.lock.acquire()
	if f.signaled {
		f.lock.release()
		return
	}
	f.timestamp_ns = time.monotonic_ns()
	katomic.store(mut &f.signaled, true)
	f.notify_events_locked()

	// Wake every registered waiter
	for mut w in f.waiters {
		if !w.triggered {
			w.triggered = true
			w.callback(fence)
		}
	}

	f.lock.release()
}

// Signal a fence with an error code. Marks the fence as signaled with the
// given error and wakes all waiters. Used when GPU work fails.
pub fn signal_error(fence &DmaFence, err int) {
	if fence == unsafe { nil } {
		return
	}

	mut f := unsafe { fence }
	f.lock.acquire()
	// A completed fence's result is final. A losing shutdown/error producer
	// must not change the status already observed by its waiters.
	if f.signaled {
		f.lock.release()
		return
	}
	f.error = err
	f.timestamp_ns = time.monotonic_ns()
	katomic.store(mut &f.signaled, true)
	f.notify_events_locked()

	for mut w in f.waiters {
		if !w.triggered {
			w.triggered = true
			w.callback(fence)
		}
	}

	f.lock.release()
}

// Check whether a fence has been signaled (lock-free read).
pub fn is_signaled(fence &DmaFence) bool {
	if fence == unsafe { nil } {
		return true // a null fence is considered signaled
	}
	return katomic.load(&fence.signaled)
}

pub fn get_error(fence &DmaFence) int {
	if fence == unsafe { nil } {
		return 0
	}
	mut f := unsafe { fence }
	f.lock.acquire()
	error := f.error
	f.lock.release()
	return error
}

// Busy-wait for a fence to become signaled, with a timeout in nanoseconds.
// Returns true if the fence was signaled before the timeout expired.
pub fn wait(fence &DmaFence, timeout_ns u64) bool {
	if fence == unsafe { nil } {
		return true
	}

	if is_signaled(fence) {
		return true
	}

	deadline := time.monotonic_ns() + timeout_ns

	for time.monotonic_ns() < deadline {
		if is_signaled(fence) {
			return true
		}
		// Let completion workers run while this kernel-side wait is pending.
		sched.reschedule()
	}

	// Final check after timeout
	return is_signaled(fence)
}

pub fn now_ns() u64 {
	return time.monotonic_ns()
}

// Register a waiter callback on a fence. If the fence is already
// signaled the callback fires immediately.
pub fn add_waiter(fence &DmaFence, waiter &FenceWaiter) {
	if fence == unsafe { nil } {
		return
	}

	mut f := unsafe { fence }
	f.lock.acquire()

	if f.signaled {
		mut w := unsafe { waiter }
		w.triggered = true
		w.callback(fence)
		f.lock.release()
		return
	}

	f.waiters << unsafe { waiter }
	f.lock.release()
}

fn next_namespace_handle(handle u32) ?u32 {
	if handle == ~u32(0) { return none }
	return handle + 1
}

// Allocate a sync object in one DRM open-file namespace. Different opens may
// receive the same numeric handle, but never resolve each other's objects.
pub fn new_syncobj(owner u64) ?&SyncObj {
	return new_syncobj_with_flags(owner, false)
}

// Complete private initialization before making the object reachable by a
// guessed handle. Only unpublished allocations may be freed on failure;
// published metadata keeps the existing lifetime for in-flight snapshots.
pub fn new_syncobj_with_flags(owner u64, signaled bool) ?&SyncObj {
	if owner == 0 {
		return none
	}
	allocation := memory.malloc_packed_fallible(sizeof(SyncObj))
	if allocation == unsafe { nil } { return none }
	mut obj := unsafe { &SyncObj(allocation) }
	unsafe { *obj = SyncObj{} }
	obj.namespace = SyncobjHandle{ owner: owner, object: obj }
	mut published := false
	defer {
		if !published {
			// This fresh private stub has never had waiters or other holders.
			if obj.fence != unsafe { nil } { memory.free(voidptr(obj.fence)) }
			memory.free(allocation)
		}
	}
	if signaled {
		obj.fence = new_private_stub(now_ns()) or { return none }
	}
	insert_handle(unsafe { &obj.namespace }) or { return none }
	published = true
	return obj
}

// Add a new name for the same mutable sync object, not a fence snapshot.
pub fn import_syncobj(owner u64, obj &SyncObj) ?u32 {
	if owner == 0 || obj == unsafe { nil } { return none }
	allocation := memory.malloc_packed_fallible(sizeof(SyncobjHandle))
	if allocation == unsafe { nil } { return none }
	mut entry := unsafe { &SyncobjHandle(allocation) }
	unsafe { *entry = SyncobjHandle{ owner: owner, object: obj, allocated: true } }
	return insert_handle(entry) or {
		// The namespace lock is released before failure cleanup.
		memory.free(allocation)
		return none
	}
}

// Prepared entries transfer into the namespace under its lock. Keys stay
// immutable until unlink; callers never borrow an entry pointer from lookup.
fn insert_handle(entry &SyncobjHandle) ?u32 {
	syncobj_lock.acquire()
	defer { syncobj_lock.release() }
	mut e := unsafe { entry }
	owner := e.owner

	// Sorted owner/handle order lets one pass find the lowest nonzero free
	// handle without a fixed table or auxiliary namespace allocations.
	mut previous := &SyncobjHandle(unsafe { nil })
	mut cursor := unsafe { syncobj_head }
	for cursor != unsafe { nil } && cursor.owner < owner {
		previous = unsafe { cursor }
		cursor = unsafe { cursor.next }
	}
	mut handle := u32(1)
	for cursor != unsafe { nil } && cursor.owner == owner {
		if cursor.handle > handle { break }
		handle = next_namespace_handle(handle) or { return none }
		previous = unsafe { cursor }
		cursor = unsafe { cursor.next }
	}
	e.handle = handle
	if !e.allocated { unsafe { e.object.handle = handle } }
	e.next = unsafe { cursor }
	if previous == unsafe { nil } { syncobj_head = e }
	else { unsafe { previous.next = e } }
	return handle
}

// Look up a sync object by its owner and per-open handle.
pub fn lookup(owner u64, handle u32) ?&SyncObj {
	if owner == 0 || handle == 0 {
		return none
	}

	syncobj_lock.acquire()
	defer { syncobj_lock.release() }
	mut cursor := unsafe { syncobj_head }
	for cursor != unsafe { nil } {
		if cursor.owner > owner || (cursor.owner == owner && cursor.handle > handle) { break }
		if cursor.owner == owner && cursor.handle == handle { return unsafe { cursor.object } }
		cursor = unsafe { cursor.next }
	}
	return none
}

// Destroy one object only when it belongs to the calling open file.
pub fn destroy(owner u64, handle u32) bool {
	if owner == 0 || handle == 0 { return false }
	syncobj_lock.acquire()
	mut previous := &SyncobjHandle(unsafe { nil })
	mut cursor := unsafe { syncobj_head }
	mut removed := &SyncobjHandle(unsafe { nil })
	for cursor != unsafe { nil } {
		if cursor.owner > owner || (cursor.owner == owner && cursor.handle > handle) { break }
		if cursor.owner == owner && cursor.handle == handle {
			if previous == unsafe { nil } { syncobj_head = unsafe { cursor.next } }
			else { unsafe { previous.next = cursor.next } }
			unsafe { cursor.next = nil }
			removed = unsafe { cursor }
			break
		}
		previous = unsafe { cursor }
		cursor = unsafe { cursor.next }
	}
	syncobj_lock.release()
	if removed == unsafe { nil } { return false }
	if removed.allocated { memory.free(voidptr(removed)) }
	return true
}

// Final DRM-file release drops the complete handle namespace. Objects stay
// allocated for now so an in-flight waiter that already holds a pointer cannot
// race a free; the table ownership is removed immediately.
pub fn destroy_owner(owner u64) {
	if owner == 0 {
		return
	}
	syncobj_lock.acquire()
	mut previous := &SyncobjHandle(unsafe { nil })
	mut cursor := unsafe { syncobj_head }
	mut retired := &SyncobjHandle(unsafe { nil })
	for cursor != unsafe { nil } && cursor.owner < owner {
		previous = unsafe { cursor }
		cursor = unsafe { cursor.next }
	}
	for cursor != unsafe { nil } && cursor.owner == owner {
		next := unsafe { cursor.next }
		if previous == unsafe { nil } { syncobj_head = unsafe { next } }
		else { unsafe { previous.next = next } }
		if cursor.allocated {
			unsafe { cursor.next = retired }
			retired = unsafe { cursor }
		} else { unsafe { cursor.next = nil } }
		cursor = unsafe { next }
	}
	syncobj_lock.release()
	// Only detached alias links are owned here. Object/fence metadata remains
	// valid for captures, other namespaces and exported opaque descriptors.
	for retired != unsafe { nil } {
		next := unsafe { retired.next }
		memory.free(voidptr(retired))
		retired = unsafe { next }
	}
}

// Atomically replace the fence inside a sync object.
pub fn replace_fence(obj &SyncObj, fence &DmaFence) {
	if obj == unsafe { nil } {
		return
	}

	mut o := unsafe { obj }
	o.lock.acquire()
	o.fence = unsafe { fence }
	// Binary replacement discards the previous timeline lookup chain. Fence
	// allocations already captured by submissions/waiters remain retained.
	o.timeline_points.clear()
	o.publish_captures_locked(fence)
	o.lock.release()
}

// Snapshot a binary syncobj fence under its object lock. Fence allocations
// are intentionally retained after handle destruction, so the returned
// pointer remains valid for an in-flight submission.
pub fn get_fence(obj &SyncObj) ?&DmaFence {
	if obj == unsafe { nil } {
		return none
	}
	mut o := unsafe { obj }
	o.lock.acquire()
	defer {
		o.lock.release()
	}
	if o.fence == unsafe { nil } {
		return none
	}
	return unsafe { o.fence }
}

// Associate an Asahi timeline point with a fence. The unstable Asahi UAPI
// uses timeline syncobjs internally even when generic DRM timeline ioctls are
// unavailable. Different Mesa contexts can publish unique points out of
// order, so keep the exact value-to-fence mapping without imposing insertion
// order.
pub fn add_timeline_point(obj &SyncObj, value u64, fence &DmaFence) bool {
	if obj == unsafe { nil } || fence == unsafe { nil } || value == 0 {
		return false
	}
	mut o := unsafe { obj }
	o.lock.acquire()
	defer {
		o.lock.release()
	}
	for point in o.timeline_points {
		if point.value == value {
			return false
		}
	}
	o.timeline_points << TimelinePoint{
		value: value
		fence: unsafe { fence }
	}
	return true
}

// Resolve a submitted point. An exact match is preferred. If contexts publish
// timeline points out of order and the requested lower point has not arrived
// yet, wait on the nearest later fence conservatively. This mirrors the fence
// chain behaviour Mesa relies on instead of rejecting the submission.
pub fn get_timeline_fence(obj &SyncObj, value u64) ?&DmaFence {
	if obj == unsafe { nil } || value == 0 {
		return none
	}
	mut o := unsafe { obj }
	o.lock.acquire()
	defer {
		o.lock.release()
	}
	mut later_value := ~u64(0)
	mut later_fence := &DmaFence(unsafe { nil })
	for point in o.timeline_points {
		if point.value == value && point.fence != unsafe { nil } {
			return unsafe { point.fence }
		}
		if point.value > value && point.value < later_value
			&& point.fence != unsafe { nil } {
			later_value = point.value
			later_fence = unsafe { point.fence }
		}
	}
	if later_fence != unsafe { nil } {
		return later_fence
	}
	return none
}
