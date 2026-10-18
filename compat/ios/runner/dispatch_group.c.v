// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Membership owns one internal reference while nonempty. Notifications own
// their queue and copied block until submission or shutdown cancellation.
struct DispatchGroup {
mut:
	isa u64
	refs u64 = 1
	members u64
	generation u64
	context voidptr
	finalizer DispatchFunction = unsafe { nil }
	head &DispatchGroupWork = unsafe { nil }
	tail &DispatchGroupWork = unsafe { nil }
}

struct DispatchGroupWork {
mut:
	next &DispatchGroupWork = unsafe { nil }
	queue u64
	group u64
	block u64
	context voidptr
	function DispatchFunction = unsafe { nil }
}

fn dispatch_group_locked(identity u64) &DispatchGroup {
	return dispatch_runtime.groups[identity] or { panic('iOS: invalid dispatch group') }
}

fn darwin_dispatch_group_create() u64 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	if dispatch_runtime.stopping { panic('iOS: dispatch group created during image shutdown') }
	mut group := unsafe { &DispatchGroup(C.calloc(1, sizeof(DispatchGroup))) }
	if group == unsafe { nil } { panic('iOS: cannot allocate dispatch group') }
	group.isa = dispatch_runtime.group_class
	group.refs = 1
	dispatch_runtime.groups[u64(group)] = group
	return u64(group)
}

// Returns removed storage for its caller to free after unlocking. A completed
// group has no pending notifications: leave detaches them before dropping its
// membership reference. Finalizers run as queue work, never under this mutex.
fn dispatch_group_drop_locked(mut group DispatchGroup) bool {
	group.refs--
	if group.refs != 0 { return false }
	if group.members != 0 || group.head != unsafe { nil } { panic('iOS: dispatch group destroyed while active') }
	dispatch_runtime.groups.delete(u64(&group))
	if !dispatch_runtime.stopping && group.finalizer != unsafe { nil } && group.context != unsafe { nil } {
		dispatch_add_locked(dispatch_default_root_locked(), 0, 0, group.context, group.finalizer, false)
	}
	return true
}

fn dispatch_group_enter_locked(mut group DispatchGroup) {
	if group.members == ~u64(0) { panic('iOS: dispatch group membership overflow') }
	if group.members == 0 { group.refs++ }
	group.members++
}

fn darwin_dispatch_group_enter(identity u64) {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	if dispatch_runtime.stopping { panic('iOS: dispatch group entered during image shutdown') }
	dispatch_group_enter_locked(mut dispatch_group_locked(identity))
}

fn dispatch_group_work_call(context voidptr) {
	work := unsafe { &DispatchGroupWork(context) }
	if work.block != 0 { block_invoke_void(work.block) } else { work.function(work.context) }
}

fn dispatch_group_work_cleanup(context voidptr) {
	work := unsafe { &DispatchGroupWork(context) }
	// Measured native ordering: disposal is part of the member's lifetime.
	block_release(work.block)
	if work.group != 0 { darwin_dispatch_group_leave(work.group) }
	C.free(work)
}

fn dispatch_group_notifications(head &DispatchGroupWork, cancel bool) {
	mut work := unsafe { &DispatchGroupWork(head) }
	for work != unsafe { nil } {
		next := work.next
		queue := work.queue
		if cancel { dispatch_group_work_cleanup(work) } else {
			dispatch_submit_owned(queue, work, dispatch_group_work_call, dispatch_group_work_cleanup)
		}
		// Submission may already have executed and freed work on another thread.
		darwin_dispatch_release(queue)
		work = next
	}
}

fn darwin_dispatch_group_leave(identity u64) {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	mut group := dispatch_group_locked(identity)
	if group.members == 0 { panic('iOS: unbalanced dispatch_group_leave') }
	group.members--
	if group.members != 0 { C.pthread_mutex_unlock(dispatch_runtime.mutex); return }
	group.generation++
	head := group.head
	unsafe { group.head = nil; group.tail = nil }
	removed := dispatch_group_drop_locked(mut group)
	C.pthread_cond_broadcast(dispatch_runtime.condition)
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	if removed { C.free(group) }
	dispatch_group_notifications(head, false)
}

fn darwin_dispatch_group_wait(identity u64, deadline u64) i64 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	mut group := dispatch_group_locked(identity)
	if group.members == 0 { C.pthread_mutex_unlock(dispatch_runtime.mutex); return 0 }
	generation := group.generation
	group.refs++
	mut result := i64(0)
	for group.generation == generation {
		remaining := dispatch_remaining(deadline)
		if remaining == 0 { result = 49; break } // Native Darwin ETIMEDOUT.
		if dispatch_runtime.stopping { panic('iOS: an application thread still waits on dispatch_group_wait at shutdown') }
		dispatch_wait_interval(dispatch_runtime.condition, dispatch_runtime.mutex, remaining)
	}
	removed := dispatch_group_drop_locked(mut group)
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	if removed { C.free(group) }
	return result
}

fn dispatch_group_work_new(block u64, context voidptr, function DispatchFunction) &DispatchGroupWork {
	if block == 0 && function == unsafe { nil } { panic('iOS: null dispatch group callback') }
	mut work := unsafe { &DispatchGroupWork(C.calloc(1, sizeof(DispatchGroupWork))) }
	if work == unsafe { nil } { panic('iOS: cannot allocate dispatch group work') }
	work.block = block_copy(block)
	work.context = context
	work.function = function
	return work
}

fn dispatch_group_submit(identity u64, queue_identity u64, block u64, context voidptr, function DispatchFunction, notification bool) {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	mut work := dispatch_group_work_new(block, context, function)
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	if dispatch_runtime.stopping {
		C.pthread_mutex_unlock(dispatch_runtime.mutex)
		dispatch_group_work_cleanup(work)
		return
	}
	mut group := dispatch_group_locked(identity)
	mut queue := dispatch_queue_locked(queue_identity)
	if notification {
		work.queue = queue_identity
		if !queue.immortal { queue.refs++ }
		if group.members != 0 {
			if group.tail == unsafe { nil } { group.head = work } else { group.tail.next = work }
			group.tail = work
			C.pthread_mutex_unlock(dispatch_runtime.mutex)
			return
		}
		C.pthread_mutex_unlock(dispatch_runtime.mutex)
		dispatch_group_notifications(work, false)
	} else {
		dispatch_group_enter_locked(mut group)
		work.group = identity
		mut job := dispatch_add_locked(queue, 0, 0, work, dispatch_group_work_call, false)
		job.cleanup = dispatch_group_work_cleanup
		C.pthread_mutex_unlock(dispatch_runtime.mutex)
	}
}

fn darwin_dispatch_group_async(group u64, queue u64, block u64) {
	dispatch_group_submit(group, queue, block, unsafe { nil }, unsafe { nil }, false)
}
fn darwin_dispatch_group_async_f(group u64, queue u64, context voidptr, function DispatchFunction) {
	dispatch_group_submit(group, queue, 0, context, function, false)
}
fn darwin_dispatch_group_notify(group u64, queue u64, block u64) {
	dispatch_group_submit(group, queue, block, unsafe { nil }, unsafe { nil }, true)
}
fn darwin_dispatch_group_notify_f(group u64, queue u64, context voidptr, function DispatchFunction) {
	dispatch_group_submit(group, queue, 0, context, function, true)
}

// Workers have joined and queued members have been cancelled first. Dispose
// pending notifications before retiring the runtime's block/class metadata.
fn dispatch_group_stop() {
	if dispatch_runtime == unsafe { nil } { return }
	for {
		C.pthread_mutex_lock(dispatch_runtime.mutex)
		mut head := unsafe { &DispatchGroupWork(nil) }
		for _, mut group in dispatch_runtime.groups {
			if group.head != unsafe { nil } {
				head = group.head
				unsafe { group.head = nil; group.tail = nil }
				break
			}
		}
		C.pthread_mutex_unlock(dispatch_runtime.mutex)
		if head == unsafe { nil } { return }
		dispatch_group_notifications(head, true)
	}
}

fn dispatch_group_symbol(symbol string) ?u64 {
	return match symbol {
		'_dispatch_group_create' { u64(unsafe { voidptr(darwin_dispatch_group_create) }) }
		'_dispatch_group_enter' { u64(unsafe { voidptr(darwin_dispatch_group_enter) }) }
		'_dispatch_group_leave' { u64(unsafe { voidptr(darwin_dispatch_group_leave) }) }
		'_dispatch_group_wait' { u64(unsafe { voidptr(darwin_dispatch_group_wait) }) }
		'_dispatch_group_async' { u64(unsafe { voidptr(darwin_dispatch_group_async) }) }
		'_dispatch_group_async_f' { u64(unsafe { voidptr(darwin_dispatch_group_async_f) }) }
		'_dispatch_group_notify' { u64(unsafe { voidptr(darwin_dispatch_group_notify) }) }
		'_dispatch_group_notify_f' { u64(unsafe { voidptr(darwin_dispatch_group_notify_f) }) }
		else { return none }
	}
}
