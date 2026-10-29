// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Block work uses a private serial executor. Serial execution satisfies every
// configured upper bound; dependencies, priorities and NSOperation submission
// remain unsupported. Jobs pin both the queue and their captured work.
struct FoundationOperationQueue {
mut:
	backing u64
	mutex voidptr
	condition voidptr
	pending u64
	suspended bool
}

struct FoundationQueueJob {
	owner u64
	context voidptr
	run DispatchFunction
	cleanup DispatchFunction
}

fn ns_operation_queue_types(name string, meta bool, selector string) ?string {
	if name != 'NSOperationQueue' { return none }
	// currentQueue/mainQueue need main-queue singleton ownership too. Keep
	// those selectors absent until that lifecycle is implemented.
	if meta { return none }
	return match selector {
		'name' { '@16@0:8' }
		'setName:' { 'v24@0:8@16' }
		'maxConcurrentOperationCount' { 'q16@0:8' }
		'setMaxConcurrentOperationCount:' { 'v24@0:8q16' }
		'addOperationWithBlock:' { 'v24@0:8@?16' }
		'operationCount' { 'Q16@0:8' }
		'isSuspended' { 'B16@0:8' }
		'setSuspended:' { 'v20@0:8B16' }
		'waitUntilAllOperationsAreFinished' { 'v16@0:8' }
		else { return none }
	}
}

fn ns_operation_queue_state(object u64) &FoundationOperationQueue {
	if dispatch_runtime == unsafe { nil } { panic('iOS: operation scheduling requires the dispatch runtime') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut header := obj_header(object)
	if header.destroyed || header.destroying || (!objc_is_kind(object, ios_runtime.names['NSOperationQueue']) && header.operation_queue == unsafe { nil }) {
		panic('iOS: operation scheduling requires a live queue')
	}
	if header.operation_queue != unsafe { nil } { return header.operation_queue }
	mut state := unsafe { &FoundationOperationQueue(C.calloc(1, sizeof(FoundationOperationQueue))) }
	if state == unsafe { nil } { panic('iOS: cannot allocate operation queue executor') }
	state.mutex = C.calloc(1, C.ios_sizeof_mutex())
	state.condition = C.calloc(1, C.ios_sizeof_cond())
	if state.mutex == unsafe { nil } || state.condition == unsafe { nil }
		|| C.ios_mutex_create(state.mutex, 0) != 0 || C.pthread_cond_init(state.condition, unsafe { nil }) != 0 {
		panic('iOS: cannot initialize operation queue executor')
	}
	state.backing = darwin_dispatch_queue_create(c'org.vinix.operation-queue', 0)
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	dispatch_queue_locked(state.backing).operation_owner = object
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	header.operation_queue = state
	return state
}

// Internal identity for Foundation callback delivery; each running job owns
// the ObjC object until its cleanup has finished, including capture disposal.
fn ns_operation_queue_current() u64 {
	if dispatch_runtime == unsafe { nil } { return 0 }
	queue := dispatch_current_queue()
	return if queue == unsafe { nil } { u64(0) } else { queue.operation_owner }
}

fn ns_operation_queue_run(context voidptr) {
	job := unsafe { &FoundationQueueJob(context) }
	job.run(job.context)
}

fn ns_operation_queue_cleanup(context voidptr) {
	job := unsafe { &FoundationQueueJob(context) }
	owner := job.owner
	mut state := obj_header(owner).operation_queue
	// Application block/context destructors can reenter this queue. Never
	// hold the count mutex or scheduler mutex while calling them.
	if job.cleanup != unsafe { nil } { job.cleanup(job.context) }
	C.pthread_mutex_lock(state.mutex)
	if state.pending == 0 { panic('iOS: operation queue count underflow') }
	state.pending--
	C.pthread_cond_broadcast(state.condition)
	C.pthread_mutex_unlock(state.mutex)
	C.free(context)
	objc_release(owner)
}

fn ns_operation_queue_submit(object u64, context voidptr, run DispatchFunction, cleanup DispatchFunction) {
	if run == unsafe { nil } { panic('iOS: operation queue requires work') }
	owner := objc_retain(object)
	mut state := ns_operation_queue_state(owner)
	mut job := unsafe { &FoundationQueueJob(C.calloc(1, sizeof(FoundationQueueJob))) }
	if job == unsafe { nil } { panic('iOS: cannot allocate queued operation') }
	unsafe { *job = FoundationQueueJob{owner: owner, context: context, run: run, cleanup: cleanup} }
	C.pthread_mutex_lock(state.mutex)
	if state.pending == ~u64(0) { panic('iOS: operation queue count overflow') }
	state.pending++
	C.pthread_mutex_unlock(state.mutex)
	dispatch_submit_owned(state.backing, job, ns_operation_queue_run, ns_operation_queue_cleanup)
}

fn ns_operation_queue_block_free(context voidptr) { block_release(u64(context)) }

fn ns_operation_queue_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if object in ios_runtime.classes || !objc_is_kind(object, ios_runtime.names['NSOperationQueue']) { return false }
	if selector !in ['addOperationWithBlock:', 'operationCount', 'isSuspended', 'setSuspended:', 'waitUntilAllOperationsAreFinished']! { return false }
	objc_retain(object)
	defer { objc_release(object) }
	mut state := ns_operation_queue_state(object)
	if selector == 'addOperationWithBlock:' {
		if frame.x[2] == 0 || !is_block(frame.x[2]) { panic('iOS: operation queue requires a block') }
		copied := block_copy(frame.x[2])
		ns_operation_queue_submit(object, unsafe { voidptr(copied) }, dispatch_block, ns_operation_queue_block_free)
		return true
	}
	if selector == 'waitUntilAllOperationsAreFinished' && ns_operation_queue_current() == object {
		panic('iOS: an operation cannot wait for its own queue')
	}
	C.pthread_mutex_lock(state.mutex)
	match selector {
		'operationCount' { frame.x[0] = state.pending }
		'isSuspended' { frame.x[0] = u64(state.suspended) }
		'setSuspended:' {
			wanted := u8(frame.x[2]) != 0
			if wanted != state.suspended {
				if wanted { darwin_dispatch_suspend(state.backing) } else { darwin_dispatch_resume(state.backing) }
				state.suspended = wanted
			}
		}
		else {
			for state.pending != 0 { C.pthread_cond_wait(state.condition, state.mutex) }
		}
	}
	C.pthread_mutex_unlock(state.mutex)
	return true
}

fn ns_operation_queue_dispose(mut header ObjHeader) {
	state := header.operation_queue
	if state == unsafe { nil } { return }
	header.operation_queue = unsafe { nil }
	if state.pending != 0 { panic('iOS: destroying an operation queue with pending work') }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	dispatch_queue_locked(state.backing).operation_owner = 0
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	if state.suspended { darwin_dispatch_resume(state.backing) }
	darwin_dispatch_release(state.backing)
	C.pthread_cond_destroy(state.condition); C.pthread_mutex_destroy(state.mutex)
	C.free(state.condition); C.free(state.mutex); C.free(state)
}
