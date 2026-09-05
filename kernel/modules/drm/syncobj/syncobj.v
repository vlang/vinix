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

pub struct SyncObj {
pub mut:
	handle u32
	fence  &DmaFence = unsafe { nil }
	lock   klock.Lock
mut:
	owner u64
}

const syncobj_max_objects = u32(1024)

__global (
	syncobj_table   [1024]&SyncObj
	syncobj_lock    klock.Lock
)

// Create a new DMA fence with the given context and sequence number.
pub fn new_fence(context u64, seqno u64) &DmaFence {
	return &DmaFence{
		seqno:   seqno
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
