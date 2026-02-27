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
}

__global (
	syncobj_counter = u32(1)
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

// Allocate a new sync object and insert it into the global table.
pub fn new_syncobj() ?&SyncObj {
	syncobj_lock.acquire()
	defer {
		syncobj_lock.release()
	}

	handle := syncobj_counter
	syncobj_counter++

	if handle >= 1024 {
		return none
	}

	mut obj := &SyncObj{
		handle: handle
	}

	syncobj_table[handle] = obj
	return obj
}

// Look up a sync object by handle.
pub fn lookup(handle u32) ?&SyncObj {
	if handle == 0 || handle >= 1024 {
		return none
	}

	syncobj_lock.acquire()
	obj := syncobj_table[handle]
	syncobj_lock.release()

	if obj == unsafe { nil } {
		return none
	}
	return obj
}

// Destroy a sync object, removing it from the global table.
pub fn destroy(handle u32) {
	syncobj_lock.acquire()
	if handle > 0 && handle < 1024 {
		syncobj_table[handle] = unsafe { nil }
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
