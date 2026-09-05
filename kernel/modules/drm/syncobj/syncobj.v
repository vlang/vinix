@[has_globals]
module syncobj

// DRM sync objects and DMA fences for GPU synchronization.
// Fences represent points in a GPU command stream; sync objects
// wrap fences so user-space can wait on / signal them via ioctls.

import klock
import katomic
import aarch64.timer

pub struct FenceWaiter {
pub mut:
	callback  fn (&DmaFence) = unsafe { nil }
	triggered bool
}

pub struct DmaFence {
pub mut:
	seqno    u64
	signaled bool
	error    int // 0 = success, negative = error code
	context  u64
	lock     klock.Lock
	waiters  []&FenceWaiter
}

struct TimelinePoint {
	value u64
	fence &DmaFence = unsafe { nil }
}

pub struct SyncObj {
pub mut:
	handle u32
	fence  &DmaFence = unsafe { nil }
	lock   klock.Lock
mut:
	owner           u64
	timeline_points []TimelinePoint
}

const syncobj_max_objects = u32(1024)

__global (
	syncobj_table [1024]&SyncObj
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
	f.signaled = true

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
	f.error = err
	f.signaled = true

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

	deadline := timer.get_ns() + timeout_ns

	for timer.get_ns() < deadline {
		if is_signaled(fence) {
			return true
		}
		// Yield the CPU briefly while spinning
		asm volatile aarch64 {
			yield
			; ; ; memory
		}
	}

	// Final check after timeout
	return is_signaled(fence)
}

pub fn now_ns() u64 {
	return timer.get_ns()
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

fn handle_in_use_locked(owner u64, handle u32) bool {
	for obj in syncobj_table {
		if obj != unsafe { nil } && obj.owner == owner && obj.handle == handle {
			return true
		}
	}
	return false
}

// Allocate a sync object in one DRM open-file namespace. Different opens may
// receive the same numeric handle, but never resolve each other's objects.
pub fn new_syncobj(owner u64) ?&SyncObj {
	if owner == 0 {
		return none
	}
	syncobj_lock.acquire()
	defer {
		syncobj_lock.release()
	}

	mut slot := u32(syncobj_max_objects)
	for i := u32(0); i < syncobj_max_objects; i++ {
		if syncobj_table[i] == unsafe { nil } {
			slot = i
			break
		}
	}
	if slot == syncobj_max_objects {
		return none
	}

	// Recycle the lowest free handle in this open-file namespace.
	mut handle := u32(0)
	for i := u32(1); i < syncobj_max_objects; i++ {
		if !handle_in_use_locked(owner, i) {
			handle = i
			break
		}
	}
	if handle == 0 {
		return none // table exhausted
	}

	mut obj := &SyncObj{
		handle: handle
		owner: owner
	}

	syncobj_table[slot] = obj
	return obj
}

// Look up a sync object by its owner and per-open handle.
pub fn lookup(owner u64, handle u32) ?&SyncObj {
	if owner == 0 || handle == 0 || handle >= syncobj_max_objects {
		return none
	}

	syncobj_lock.acquire()
	defer { syncobj_lock.release() }
	for i := u32(0); i < syncobj_max_objects; i++ {
		obj := syncobj_table[i]
		if obj != unsafe { nil } && obj.owner == owner && obj.handle == handle {
			return unsafe { obj }
		}
	}
	return none
}

// Destroy one object only when it belongs to the calling open file.
pub fn destroy(owner u64, handle u32) bool {
	syncobj_lock.acquire()
	defer { syncobj_lock.release() }
	for i := u32(0); i < syncobj_max_objects; i++ {
		obj := syncobj_table[i]
		if obj != unsafe { nil } && obj.owner == owner && obj.handle == handle {
			syncobj_table[i] = unsafe { nil }
			return true
		}
	}
	return false
}

// Final DRM-file release drops the complete handle namespace. Objects stay
// allocated for now so an in-flight waiter that already holds a pointer cannot
// race a free; the table ownership is removed immediately.
pub fn destroy_owner(owner u64) {
	if owner == 0 {
		return
	}
	syncobj_lock.acquire()
	for i := u32(0); i < syncobj_max_objects; i++ {
		obj := syncobj_table[i]
		if obj != unsafe { nil } && obj.owner == owner {
			syncobj_table[i] = unsafe { nil }
		}
	}
	syncobj_lock.release()
}

// Atomically replace the fence inside a sync object.
pub fn replace_fence(obj &SyncObj, fence &DmaFence) {
	if obj == unsafe { nil } {
		return
	}

	mut o := unsafe { obj }
	o.lock.acquire()
	o.fence = unsafe { fence }
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

// Resolve a previously submitted point. Keeping exact points avoids treating
// an out-of-order later fence as completion of an earlier dependency.
pub fn get_timeline_fence(obj &SyncObj, value u64) ?&DmaFence {
	if obj == unsafe { nil } || value == 0 {
		return none
	}
	mut o := unsafe { obj }
	o.lock.acquire()
	defer {
		o.lock.release()
	}
	for point in o.timeline_points {
		if point.value == value && point.fence != unsafe { nil } {
			return unsafe { point.fence }
		}
	}
	return none
}
