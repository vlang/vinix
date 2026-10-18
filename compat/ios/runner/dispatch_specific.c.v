// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct DispatchSpecific {
mut:
	key u64
	context voidptr
	destructor DispatchFunction = unsafe { nil }
	called bool
	next &DispatchSpecific = unsafe { nil }
}

fn dispatch_specific_find(head &DispatchSpecific, key u64) &DispatchSpecific {
	mut entry := unsafe { &DispatchSpecific(head) }
	for entry != unsafe { nil } {
		if entry.key == key { return entry }
		entry = entry.next
	}
	return unsafe { nil }
}

fn dispatch_specific_call(context voidptr) {
	mut entry := unsafe { &DispatchSpecific(context) }
	entry.called = true
	entry.destructor(entry.context)
}

fn dispatch_specific_cleanup(context voidptr) {
	entry := unsafe { &DispatchSpecific(context) }
	if !entry.called { entry.destructor(entry.context) }
	C.free(entry)
}

// Detaching a list transfers ownership to this path. Both execution and
// cancellation consume each destructor once, outside the scheduler mutex.
fn dispatch_specific_retire(head &DispatchSpecific) {
	mut entry := unsafe { &DispatchSpecific(head) }
	for entry != unsafe { nil } {
		next := entry.next
		if entry.destructor == unsafe { nil } {
			C.free(entry)
		} else {
			queue := darwin_dispatch_get_global_queue(0, 0)
			dispatch_submit_owned(queue, entry, dispatch_specific_call, dispatch_specific_cleanup)
		}
		entry = next
	}
}

fn darwin_dispatch_queue_set_specific(identity u64, key u64, context voidptr, destructor DispatchFunction) {
	if key == 0 { return }
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	mut replacement := unsafe { &DispatchSpecific(nil) }
	if context != unsafe { nil } {
		replacement = unsafe { &DispatchSpecific(C.calloc(1, sizeof(DispatchSpecific))) }
		if replacement == unsafe { nil } { panic('iOS: cannot allocate dispatch queue-specific context') }
		replacement.key = key
		replacement.context = context
		replacement.destructor = destructor
	}
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	mut queue := dispatch_queue_locked(identity)
	if dispatch_runtime.stopping && replacement != unsafe { nil } { panic('iOS: queue-specific context installed during image shutdown') }
	mut link := unsafe { &queue.specific }
	for unsafe { *link } != unsafe { nil } && unsafe { *link }.key != key {
		link = unsafe { &(*link).next }
	}
	mut retired := unsafe { *link }
	if retired != unsafe { nil } {
		unsafe { *link = retired.next }
		retired.next = unsafe { nil }
	}
	if replacement != unsafe { nil } {
		replacement.next = queue.specific
		queue.specific = replacement
	}
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	dispatch_specific_retire(retired)
}

fn darwin_dispatch_queue_get_specific(identity u64, key u64) voidptr {
	if key == 0 { return unsafe { nil } }
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	queue := dispatch_queue_locked(identity)
	entry := dispatch_specific_find(queue.specific, key)
	return if entry == unsafe { nil } { unsafe { nil } } else { entry.context }
}

fn darwin_dispatch_get_specific(key u64) voidptr {
	if key == 0 || dispatch_runtime == unsafe { nil } { return unsafe { nil } }
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	// The main thread denotes the main queue outside explicit callbacks too.
	mut queue := if ios_runtime == unsafe { nil } { unsafe { &DispatchQueue(nil) } } else { dispatch_current_queue() }
	for queue != unsafe { nil } {
		entry := dispatch_specific_find(queue.specific, key)
		if entry != unsafe { nil } { return entry.context }
		queue = queue.target
	}
	return unsafe { nil }
}

// Called after workers stop, while application/runtime storage is still live.
// Destructors may release another queue, so rescan the registry under its lock.
fn dispatch_specific_stop() {
	if dispatch_runtime == unsafe { nil } { return }
	for {
		C.pthread_mutex_lock(dispatch_runtime.mutex)
		mut head := unsafe { &DispatchSpecific(nil) }
		for _, mut queue in dispatch_runtime.queues {
			if queue.specific != unsafe { nil } {
				head = queue.specific
				queue.specific = unsafe { nil }
				break
			}
		}
		C.pthread_mutex_unlock(dispatch_runtime.mutex)
		if head == unsafe { nil } { return }
		dispatch_specific_retire(head)
	}
}

fn dispatch_specific_symbol(symbol string) ?u64 {
	return match symbol {
		'_dispatch_get_specific' { u64(unsafe { voidptr(darwin_dispatch_get_specific) }) }
		'_dispatch_queue_get_specific' { u64(unsafe { voidptr(darwin_dispatch_queue_get_specific) }) }
		'_dispatch_queue_set_specific' { u64(unsafe { voidptr(darwin_dispatch_queue_set_specific) }) }
		else { return none }
	}
}
