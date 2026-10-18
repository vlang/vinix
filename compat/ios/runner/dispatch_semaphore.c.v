// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct DispatchSemaphore {
mut:
	isa u64
	refs u64
	initial u64
	value u64
	waiters u64
	head &DispatchSemaphoreWaiter = unsafe { nil }
	tail &DispatchSemaphoreWaiter = unsafe { nil }
	context voidptr
	finalizer DispatchFunction = unsafe { nil }
}

// Wait records live on the waiting thread's stack. The scheduler mutex guards
// both linkage and grants; removing a timeout cannot consume a later signal.
struct DispatchSemaphoreWaiter {
mut:
	previous &DispatchSemaphoreWaiter = unsafe { nil }
	next &DispatchSemaphoreWaiter = unsafe { nil }
	granted bool
}

fn dispatch_semaphore_locked(identity u64) &DispatchSemaphore {
	return dispatch_runtime.semaphores[identity] or { panic('iOS: invalid dispatch semaphore') }
}

fn darwin_dispatch_semaphore_create(value i64) u64 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if value < 0 { return 0 }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	if dispatch_runtime.stopping { panic('iOS: dispatch semaphore created during image shutdown') }
	mut semaphore := unsafe { &DispatchSemaphore(C.calloc(1, sizeof(DispatchSemaphore))) }
	if semaphore == unsafe { nil } { return 0 }
	semaphore.isa = dispatch_runtime.semaphore_class
	semaphore.refs = 1
	semaphore.initial = u64(value)
	semaphore.value = u64(value)
	dispatch_runtime.semaphores[u64(semaphore)] = semaphore
	return u64(semaphore)
}

// The caller frees removed storage after unlocking. As on native dispatch,
// the last release requires all waits to have returned and the initial token
// balance to have been restored. Finalizers execute outside this mutex.
fn dispatch_semaphore_drop_locked(mut semaphore DispatchSemaphore) bool {
	semaphore.refs--
	if semaphore.refs != 0 { return false }
	if semaphore.waiters != 0 || semaphore.value < semaphore.initial {
		panic('iOS: dispatch semaphore destroyed while in use')
	}
	dispatch_runtime.semaphores.delete(u64(&semaphore))
	if !dispatch_runtime.stopping && semaphore.finalizer != unsafe { nil } && semaphore.context != unsafe { nil } {
		dispatch_add_locked(dispatch_default_root_locked(), 0, 0, semaphore.context, semaphore.finalizer, false)
	}
	return true
}

fn dispatch_semaphore_unlink_locked(mut semaphore DispatchSemaphore, mut waiter DispatchSemaphoreWaiter) {
	if waiter.previous == unsafe { nil } { semaphore.head = waiter.next } else { waiter.previous.next = waiter.next }
	if waiter.next == unsafe { nil } { semaphore.tail = waiter.previous } else { waiter.next.previous = waiter.previous }
}

fn darwin_dispatch_semaphore_wait(identity u64, deadline u64) i64 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	mut semaphore := dispatch_semaphore_locked(identity)
	if semaphore.value != 0 {
		semaphore.value--
		C.pthread_mutex_unlock(dispatch_runtime.mutex)
		return 0
	}
	if dispatch_remaining(deadline) == 0 { C.pthread_mutex_unlock(dispatch_runtime.mutex); return 49 }
	// V heap-promotes escaped locals even through an unsafe pointer alias.
	// Explicit native stack storage lasts through this wait and its unlink.
	mut waiter := unsafe { &DispatchSemaphoreWaiter(C.__builtin_alloca(sizeof(DispatchSemaphoreWaiter))) }
	unsafe { *waiter = DispatchSemaphoreWaiter{previous: semaphore.tail} }
	if semaphore.tail == unsafe { nil } { semaphore.head = waiter } else { semaphore.tail.next = waiter }
	semaphore.tail = waiter
	semaphore.waiters++
	mut result := i64(0)
	for !waiter.granted {
		remaining := dispatch_remaining(deadline)
		if remaining == 0 {
			dispatch_semaphore_unlink_locked(mut semaphore, mut waiter)
			result = 49 // Darwin ETIMEDOUT, independent of the host's errno values.
			break
		}
		if dispatch_runtime.stopping { panic('iOS: an application thread still waits on dispatch_semaphore_wait at shutdown') }
		dispatch_wait_interval(dispatch_runtime.condition, dispatch_runtime.mutex, remaining)
	}
	semaphore.waiters--
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	return result
}

fn darwin_dispatch_semaphore_signal(identity u64) i64 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	mut semaphore := dispatch_semaphore_locked(identity)
	mut waiter := semaphore.head
	if waiter != unsafe { nil } {
		dispatch_semaphore_unlink_locked(mut semaphore, mut waiter)
		waiter.granted = true
		C.pthread_cond_broadcast(dispatch_runtime.condition)
		return 1
	}
	if semaphore.value == u64(0x7fff_ffff_ffff_ffff) { panic('iOS: dispatch semaphore signal overflow') }
	semaphore.value++
	return 0
}

fn dispatch_semaphore_symbol(symbol string) ?u64 {
	return match symbol {
		'_dispatch_semaphore_create' { u64(unsafe { voidptr(darwin_dispatch_semaphore_create) }) }
		'_dispatch_semaphore_wait' { u64(unsafe { voidptr(darwin_dispatch_semaphore_wait) }) }
		'_dispatch_semaphore_signal' { u64(unsafe { voidptr(darwin_dispatch_semaphore_signal) }) }
		else { return none }
	}
}
