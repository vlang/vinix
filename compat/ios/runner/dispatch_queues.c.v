// SPDX-License-Identifier: GPL-2.0-or-later
module main

@[heap]
struct DispatchQueue {
mut:
	identity u64
	label &char = unsafe { nil }
	target &DispatchQueue = unsafe { nil }
	refs int = 1
	busy int
	concurrent bool
	main bool
	immortal bool
	context voidptr
	finalizer DispatchFunction = unsafe { nil }
}

@[heap]
struct DispatchJob {
mut:
	queue &DispatchQueue = unsafe { nil }
	sequence u64
	when u64
	waiting bool
	block u64
	context voidptr
	function DispatchFunction = unsafe { nil }
	synchronous bool
	done bool
}

struct DispatchRuntime {
mut:
	mutex voidptr
	condition voidptr
	key u64
	queues map[u64]&DispatchQueue
	globals [5]u64
	jobs []&DispatchJob
	retired []&DispatchQueue
	workers [4]usize
	worker_count int
	sequence u64
	stopping bool
}

__global dispatch_runtime = unsafe { &DispatchRuntime(nil) }

fn dispatch_start() {
	dispatch_runtime = &DispatchRuntime{}
	dispatch_runtime.jobs.flags |= .noslices
	dispatch_runtime.retired.flags |= .noslices
	dispatch_runtime.mutex = C.calloc(1, C.ios_sizeof_mutex())
	dispatch_runtime.condition = C.calloc(1, C.ios_sizeof_cond())
	if dispatch_runtime.mutex == unsafe { nil } || dispatch_runtime.condition == unsafe { nil }
		|| C.ios_mutex_create(dispatch_runtime.mutex, 0) != 0
		|| C.pthread_cond_init(dispatch_runtime.condition, unsafe { nil }) != 0
		|| C.ios_key_create(unsafe { &dispatch_runtime.key }, unsafe { nil }) != 0 {
		panic('iOS: cannot initialize dispatch scheduler')
	}
	mut queue := dispatch_queue_allocate(c'com.apple.main-thread')
	queue.identity = darwin_dispatch_get_main_queue()
	queue.main = true
	queue.immortal = true
	dispatch_runtime.queues[queue.identity] = queue
}

fn dispatch_queue_allocate(label &char) &DispatchQueue {
	mut queue := &DispatchQueue{}
	length := if label == unsafe { nil } { usize(0) } else { darwin_strlen(label) }
	queue.label = unsafe { &char(C.calloc(1, length + 1)) }
	if queue.label == unsafe { nil } { panic('iOS: cannot copy dispatch queue label') }
	if length != 0 { unsafe { C.memcpy(queue.label, label, length) } }
	queue.identity = u64(queue)
	return queue
}

// All queue metadata and pending work are protected by the scheduler mutex.
// The lock is never held while entering application code or a block destructor.
fn dispatch_queue_locked(identity u64) &DispatchQueue {
	return dispatch_runtime.queues[identity] or { panic('iOS: invalid or released dispatch queue') }
}

fn dispatch_global_locked(index int) &DispatchQueue {
	if dispatch_runtime.globals[index] != 0 { return dispatch_queue_locked(dispatch_runtime.globals[index]) }
	label := match index {
		0 { c'com.apple.root.background-qos' }
		1 { c'com.apple.root.utility-qos' }
		2 { c'com.apple.root.default-qos' }
		3 { c'com.apple.root.user-initiated-qos' }
		else { c'com.apple.root.user-interactive-qos' }
	}
	mut queue := dispatch_queue_allocate(label)
	queue.concurrent = true
	queue.immortal = true
	dispatch_runtime.globals[index] = queue.identity
	dispatch_runtime.queues[queue.identity] = queue
	return queue
}

fn darwin_dispatch_get_global_queue(identifier i64, flags u64) u64 {
	index := match identifier {
		-32768, 9 { 0 }
		-2, 17 { 1 }
		0, 21 { 2 }
		2, 25 { 3 }
		33 { 4 }
		else { return 0 }
	}
	if flags != 0 { return 0 }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	return dispatch_global_locked(index).identity
}

fn darwin_dispatch_queue_create_with_target(label &char, attributes u64, target u64) u64 {
	if attributes != 0 { panic('iOS: dispatch queue attributes are not implemented') }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	if dispatch_runtime.stopping { panic('iOS: dispatch queue created during image shutdown') }
	mut queue := dispatch_queue_allocate(label)
	queue.target = if target == 0 { dispatch_global_locked(2) } else { dispatch_queue_locked(target) }
	if !queue.target.immortal { queue.target.refs++ }
	dispatch_runtime.queues[queue.identity] = queue
	return queue.identity
}

fn darwin_dispatch_queue_create(label &char, attributes u64) u64 {
	return darwin_dispatch_queue_create_with_target(label, attributes, 0)
}

fn dispatch_current_queue() &DispatchQueue {
	pointer := C.pthread_getspecific(dispatch_runtime.key)
	if pointer != unsafe { nil } { return unsafe { &DispatchQueue(pointer) } }
	if u64(C.pthread_self()) == ios_runtime.main_thread { return dispatch_queue_locked(darwin_dispatch_get_main_queue()) }
	return unsafe { nil }
}

fn darwin_dispatch_queue_get_label(identity u64) &char {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	if identity == 0 {
		queue := dispatch_current_queue()
		return if queue == unsafe { nil } { c'' } else { queue.label }
	}
	return dispatch_queue_locked(identity).label
}

fn darwin_dispatch_retain(identity u64) {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	mut queue := dispatch_queue_locked(identity)
	if !queue.immortal { queue.refs++ }
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
}

// Apple blocks may capture a dispatch queue as an Objective-C object. These
// queues have private V storage, so retain/release must not inspect ObjHeader.
// This does not advertise OS_dispatch_queue classes or other ObjC methods.
fn dispatch_objc_retain(identity u64) bool {
	if dispatch_runtime == unsafe { nil } { return false }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	mut queue := dispatch_runtime.queues[identity] or { return false }
	if !queue.immortal { queue.refs++ }
	return true
}

fn dispatch_objc_release(identity u64) bool {
	if dispatch_runtime == unsafe { nil } { return false }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	mut queue := dispatch_runtime.queues[identity] or { C.pthread_mutex_unlock(dispatch_runtime.mutex); return false }
	dispatch_queue_drop_locked(mut queue)
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	dispatch_retire()
	return true
}

fn dispatch_queue_drop_locked(mut queue DispatchQueue) {
	if queue.immortal { return }
	queue.refs--
	if queue.refs == 0 {
		dispatch_runtime.queues.delete(queue.identity)
		dispatch_runtime.retired << &queue
	}
}

fn dispatch_retire() {
	for {
		C.pthread_mutex_lock(dispatch_runtime.mutex)
		if dispatch_runtime.retired.len == 0 { C.pthread_mutex_unlock(dispatch_runtime.mutex); return }
		queue := dispatch_runtime.retired.pop()
		// A finalizer itself keeps the target alive until it has run.
		if !dispatch_runtime.stopping && queue.finalizer != unsafe { nil } && queue.context != unsafe { nil } {
			dispatch_add_locked(queue.target, 0, 0, queue.context, queue.finalizer, false)
		}
		if queue.target != unsafe { nil } { dispatch_queue_drop_locked(mut queue.target) }
		C.pthread_cond_broadcast(dispatch_runtime.condition)
		C.pthread_mutex_unlock(dispatch_runtime.mutex)
		C.free(queue.label)
		unsafe { free(queue) }
	}
}

fn darwin_dispatch_release(identity u64) {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	mut queue := dispatch_queue_locked(identity)
	dispatch_queue_drop_locked(mut queue)
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	dispatch_retire()
}

fn darwin_dispatch_set_context(identity u64, context voidptr) {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	mut queue := dispatch_queue_locked(identity)
	if !queue.immortal { queue.context = context }
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
}

fn darwin_dispatch_get_context(identity u64) voidptr {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	return dispatch_queue_locked(identity).context
}

fn darwin_dispatch_set_finalizer_f(identity u64, function DispatchFunction) {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	mut queue := dispatch_queue_locked(identity)
	if !queue.immortal { queue.finalizer = function }
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
}

fn dispatch_main_target(queue &DispatchQueue) bool {
	mut current := unsafe { &DispatchQueue(queue) }
	for current != unsafe { nil } {
		if current.main { return true }
		current = current.target
	}
	return false
}

fn dispatch_queue_available(queue &DispatchQueue) bool {
	mut current := unsafe { &DispatchQueue(queue) }
	for current != unsafe { nil } {
		if !current.concurrent && current.busy != 0 { return false }
		current = current.target
	}
	return true
}

fn dispatch_queue_busy(queue &DispatchQueue, change int) {
	mut current := unsafe { &DispatchQueue(queue) }
	for current != unsafe { nil } {
		current.busy += change
		current = current.target
	}
}

fn dispatch_workers_start_locked() {
	if dispatch_runtime.worker_count != 0 || dispatch_runtime.stopping { return }
	for i in 0 .. dispatch_runtime.workers.len {
		if C.pthread_create(unsafe { voidptr(&dispatch_runtime.workers[i]) }, unsafe { nil },
			unsafe { voidptr(dispatch_worker) }, unsafe { nil }) != 0 { panic('iOS: cannot start dispatch worker') }
		dispatch_runtime.worker_count++
	}
}

fn dispatch_add_locked(queue &DispatchQueue, when u64, block u64, context voidptr, function DispatchFunction, synchronous bool) &DispatchJob {
	dispatch_promote_locked()
	mut owned := unsafe { &DispatchQueue(queue) }
	if !owned.immortal { owned.refs++ }
	dispatch_runtime.sequence++
	job := &DispatchJob{queue: queue, sequence: dispatch_runtime.sequence, when: when,
		waiting: dispatch_remaining(when) != 0, block: block, context: context, function: function, synchronous: synchronous}
	dispatch_runtime.jobs << job
	if !synchronous && !dispatch_main_target(queue) { dispatch_workers_start_locked() }
	C.pthread_cond_broadcast(dispatch_runtime.condition)
	return job
}

fn dispatch_submit(identity u64, when u64, block u64, context voidptr, function DispatchFunction) {
	if block == 0 && function == unsafe { nil } { panic('iOS: null dispatch callback') }
	copied := if block != 0 { block_copy(block) } else { u64(0) }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	queue := dispatch_queue_locked(identity)
	if dispatch_runtime.stopping {
		C.pthread_mutex_unlock(dispatch_runtime.mutex)
		block_release(copied)
		return
	}
	dispatch_add_locked(queue, when, copied, context, function, false)
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
}

fn dispatch_run(job &DispatchJob) {
	previous := C.pthread_getspecific(dispatch_runtime.key)
	C.pthread_setspecific(dispatch_runtime.key, job.queue)
	pool := if !job.synchronous { objc_pool_push() } else { u64(0) }
	if job.block != 0 { block_invoke_void(job.block) } else { job.function(job.context) }
	if !job.synchronous { block_release(job.block) }
	if pool != 0 { objc_pool_pop(pool) }
	C.pthread_setspecific(dispatch_runtime.key, previous)
}

fn dispatch_finish(job &DispatchJob) {
	synchronous := job.synchronous
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	dispatch_queue_busy(job.queue, -1)
	dispatch_queue_drop_locked(mut job.queue)
	mut completed := unsafe { &DispatchJob(job) }
	completed.done = true
	C.pthread_cond_broadcast(dispatch_runtime.condition)
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	if !synchronous { unsafe { free(job) } }
	dispatch_retire()
}

// Scan submission order: a future timer is not yet queued for execution and
// cannot obstruct immediate work. Serial target chains reserve their entire
// ancestry, so sibling queues targeting one serial queue cannot overlap.
fn dispatch_promote_locked() {
	for {
		mut oldest := -1
		mut lateness := u64(0)
		for i, job in dispatch_runtime.jobs {
			if job.waiting && dispatch_remaining(job.when) == 0 {
				late := dispatch_lateness(job.when)
				if oldest < 0 || late > lateness { oldest = i; lateness = late }
			}
		}
		if oldest < 0 { return }
		mut job := dispatch_runtime.jobs[oldest]
		dispatch_runtime.jobs.delete(oldest)
		job.waiting = false
		dispatch_runtime.sequence++
		job.sequence = dispatch_runtime.sequence
		dispatch_runtime.jobs << job
	}
}

fn dispatch_ready_locked(on_main bool, maximum u64) int {
	dispatch_promote_locked()
	for i, job in dispatch_runtime.jobs {
		if job.sequence <= maximum && dispatch_main_target(job.queue) == on_main
			&& !job.waiting && dispatch_queue_available(job.queue) { return i }
	}
	return -1
}

fn dispatch_worker(argument voidptr) voidptr {
	_ = argument
	for {
		C.pthread_mutex_lock(dispatch_runtime.mutex)
		mut index := -1
		for !dispatch_runtime.stopping {
			index = dispatch_ready_locked(false, dispatch_forever)
			if index >= 0 && !dispatch_runtime.jobs[index].synchronous { break }
			mut interval := dispatch_forever
			for job in dispatch_runtime.jobs {
				if !dispatch_main_target(job.queue) {
					remaining := dispatch_remaining(job.when)
					if remaining > 0 && remaining < interval { interval = remaining }
				}
			}
			dispatch_wait_interval(dispatch_runtime.condition, dispatch_runtime.mutex, interval)
		}
		if dispatch_runtime.stopping { C.pthread_mutex_unlock(dispatch_runtime.mutex); return unsafe { nil } }
		job := dispatch_runtime.jobs[index]
		dispatch_runtime.jobs.delete(index)
		dispatch_queue_busy(job.queue, 1)
		C.pthread_mutex_unlock(dispatch_runtime.mutex)
		dispatch_run(job)
		dispatch_finish(job)
	}
	return unsafe { nil }
}

fn dispatch_sync(identity u64, block u64, context voidptr, function DispatchFunction) {
	if block == 0 && function == unsafe { nil } { panic('iOS: null dispatch_sync callback') }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	queue := dispatch_queue_locked(identity)
	if dispatch_runtime.stopping { panic('iOS: dispatch_sync during image shutdown') }
	if dispatch_main_target(queue) && u64(C.pthread_self()) == ios_runtime.main_thread { panic('iOS: dispatch_sync would deadlock the main thread') }
	current := dispatch_current_queue()
	mut ancestor := unsafe { &DispatchQueue(queue) }
	for ancestor != unsafe { nil } {
		mut executing := unsafe { &DispatchQueue(current) }
		for executing != unsafe { nil } {
			if u64(ancestor) == u64(executing) && !ancestor.concurrent { panic('iOS: recursive dispatch_sync on a serial target') }
			executing = executing.target
		}
		ancestor = ancestor.target
	}
	job := dispatch_add_locked(queue, 0, block, context, function, true)
	for {
		index := dispatch_ready_locked(dispatch_main_target(queue), dispatch_forever)
		if index >= 0 && u64(dispatch_runtime.jobs[index]) == u64(job) && !dispatch_main_target(queue) {
			dispatch_runtime.jobs.delete(index)
			dispatch_queue_busy(queue, 1)
			C.pthread_mutex_unlock(dispatch_runtime.mutex)
			dispatch_run(job)
			dispatch_finish(job)
			unsafe { free(job) }
			return
		}
		// A synchronous main queue callback is performed by the main thread.
		if job.done {
			C.pthread_mutex_unlock(dispatch_runtime.mutex)
			unsafe { free(job) }
			return
		}
		C.pthread_cond_wait(dispatch_runtime.condition, dispatch_runtime.mutex)
	}
}

fn dispatch_main_drain() bool {
	if dispatch_runtime == unsafe { nil } { return false }
	if u64(C.pthread_self()) != ios_runtime.main_thread { panic('iOS: main queue drained on a background thread') }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	dispatch_promote_locked()
	maximum := dispatch_runtime.sequence
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	mut ran := false
	for {
		C.pthread_mutex_lock(dispatch_runtime.mutex)
		index := dispatch_ready_locked(true, maximum)
		if index < 0 { C.pthread_mutex_unlock(dispatch_runtime.mutex); return ran }
		job := dispatch_runtime.jobs[index]
		dispatch_runtime.jobs.delete(index)
		dispatch_queue_busy(job.queue, 1)
		C.pthread_mutex_unlock(dispatch_runtime.mutex)
		dispatch_run(job)
		dispatch_finish(job)
		ran = true
	}
	return ran
}

fn dispatch_stop() {
	if dispatch_runtime == unsafe { nil } { return }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	dispatch_runtime.stopping = true
	C.pthread_cond_broadcast(dispatch_runtime.condition)
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	// Join before releasing captures, framework objects, TLS or Mach-O mappings.
	for i in 0 .. dispatch_runtime.worker_count {
		if C.pthread_join(unsafe { voidptr(dispatch_runtime.workers[i]) }, unsafe { nil }) != 0 { panic('iOS: cannot join dispatch worker') }
	}
	dispatch_runtime.worker_count = 0
	for {
		C.pthread_mutex_lock(dispatch_runtime.mutex)
		if dispatch_runtime.jobs.len == 0 { C.pthread_mutex_unlock(dispatch_runtime.mutex); break }
		job := dispatch_runtime.jobs.pop()
		if job.synchronous { panic('iOS: an application thread still waits on dispatch_sync at shutdown') }
		dispatch_queue_drop_locked(mut job.queue)
		C.pthread_mutex_unlock(dispatch_runtime.mutex)
		block_release(job.block)
		unsafe { free(job) }
	}
	dispatch_retire()
}

fn dispatch_free() {
	if dispatch_runtime == unsafe { nil } { return }
	for _, queue in dispatch_runtime.queues {
		if queue.busy != 0 { panic('iOS: dispatch callback still running when its image unmaps') }
		C.free(queue.label)
		unsafe { free(queue) }
	}
	C.pthread_key_delete(dispatch_runtime.key)
	C.pthread_cond_destroy(dispatch_runtime.condition)
	C.pthread_mutex_destroy(dispatch_runtime.mutex)
	C.free(dispatch_runtime.condition)
	C.free(dispatch_runtime.mutex)
	unsafe { dispatch_runtime.queues.free(); dispatch_runtime.jobs.free(); dispatch_runtime.retired.free(); free(dispatch_runtime) }
	dispatch_runtime = unsafe { nil }
}
