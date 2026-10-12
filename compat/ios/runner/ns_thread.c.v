// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

// Keep the measured 64-byte Foundation record opaque. The sidecar and TLS
// own the public state independently of isa changes or caller-supplied bytes.
struct FoundationThread {
mut:
	object u64
	name u64
	dictionary u64
	target u64
	argument u64
	selector u64
	block u64
	worker &FoundationWorker = unsafe { nil }
	stack_size u64 = 524288
	initialized bool
	started bool
	executing bool
	finished bool
	cancelled bool
	main bool
	dying bool
}

struct FoundationWorker {
mut:
	next &FoundationWorker = unsafe { nil }
	handle u64
	done bool
}

fn ns_thread_types(name string, meta bool, selector string) ?string {
	if name != 'NSThread' { return none }
	if meta {
		return match selector {
			'currentThread', 'mainThread' { '@16@0:8' }
			'isMainThread', 'isMultiThreaded' { 'B16@0:8' }
			'sleepForTimeInterval:' { 'v24@0:8d16' }
			'sleepUntilDate:' { 'v24@0:8@16' }
			'detachNewThreadSelector:toTarget:withObject:' { 'v40@0:8:16@24@32' }
			'detachNewThreadWithBlock:' { 'v24@0:8@?16' }
			'exit' { 'v16@0:8' }
			else { return none }
		}
	}
	return match selector {
		'init', 'name', 'threadDictionary' { '@16@0:8' }
		'initWithTarget:selector:object:' { '@40@0:8@16:24@32' }
		'initWithBlock:' { '@24@0:8@?16' }
		'setName:' { 'v24@0:8@16' }
		'isExecuting', 'isFinished', 'isCancelled', 'isMainThread' { 'B16@0:8' }
		'cancel', 'start', 'main' { 'v16@0:8' }
		'stackSize' { 'Q16@0:8' }
		'setStackSize:' { 'v24@0:8Q16' }
		else { return none }
	}
}

fn ns_thread_selector(object u64, selector string) bool {
	return ns_thread_matches(object) && ns_thread_types('NSThread', object in ios_runtime.classes, selector) != none
}

fn ns_thread_matches(object u64) bool {
	if object !in ios_runtime.classes { return objc_is_kind(object, ios_runtime.names['NSThread']) }
	mut cls := object
	for _ in 0 .. 128 {
		if cls == ios_runtime.names['NSThread'] { return true }
		info := ios_runtime.classes[cls] or { return false }
		cls = info.parent
		if cls == 0 { return false }
	}
	panic('iOS: cyclic thread superclass chain')
}

fn ns_thread_install(object u64, mut header ObjHeader) {
	if !objc_is_kind(object, ios_runtime.names['NSThread']) { return }
	header.thread = unsafe { &FoundationThread(C.calloc(1, sizeof(FoundationThread))) }
	if header.thread == unsafe { nil } { panic('iOS: cannot allocate Foundation thread state') }
	unsafe { *header.thread = FoundationThread{object: object} }
}

fn ns_thread_state(object u64) &FoundationThread {
	state := obj_header(object).thread
	if state == unsafe { nil } { panic('iOS: thread has no owned state') }
	return state
}

fn ns_thread_initialize(object u64, target u64, selector u64, argument u64, block u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := ns_thread_state(object)
	if state.initialized { panic('iOS: thread reinitialization is not implemented') }
	if block != 0 && !is_block(block) { panic('iOS: thread requires a block') }
	state.target = objc_retain(target)
	state.argument = objc_retain(argument)
	state.selector = selector
	state.block = block_copy(block)
	state.initialized = true
}

fn ns_thread_dispose(mut header ObjHeader) {
	state := header.thread
	if state == unsafe { nil } { return }
	if state.executing { panic('iOS: destroying an executing thread') }
	objc_release(state.name)
	objc_release(state.dictionary)
	objc_release(state.target)
	objc_release(state.argument)
	block_release(state.block)
	C.free(state)
	header.thread = unsafe { nil }
}

fn ns_thread_current() u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	pointer := C.pthread_getspecific(ios_runtime.thread_key)
	if pointer != unsafe { nil } {
		state := unsafe { &FoundationThread(pointer) }
		if state.dying { panic('iOS: currentThread during thread destruction is not implemented') }
		return state.object
	}
	on_main := darwin_pthread_main_np() != 0
	object := if on_main { objc_retain(ns_thread_main()) } else { objc_new(ios_runtime.names['NSThread']) }
	mut state := ns_thread_state(object)
	state.started = true
	state.executing = true
	state.main = on_main
	if !on_main { ios_runtime.foundation_multithreaded = true }
	if C.pthread_setspecific(ios_runtime.thread_key, state) != 0 { panic('iOS: cannot set Foundation thread TLS') }
	ios_runtime.foundation_thread_count++
	return object // The native key destructor owns this reference.
}

fn ns_thread_main() u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.foundation_main_thread == 0 {
		object := objc_new(ios_runtime.names['NSThread'])
		mut state := ns_thread_state(object)
		state.started = true; state.executing = true; state.main = true
		state.name = owned_string('Main Thread')
		ios_runtime.foundation_main_thread = object
	}
	return ios_runtime.foundation_main_thread
}

fn ns_thread_cleanup(pointer voidptr) {
	if pointer == unsafe { nil } { return }
	mut state := unsafe { &FoundationThread(pointer) }
	// pthread clears the key before invoking us. Preserve identity until the
	// captures finish; an explicit pthread_exit follows this same path.
	C.pthread_setspecific(ios_runtime.thread_key, pointer)
	C.ios_objc_initialize_lock()
	state.dying = true
	state.executing = false
	target := state.target; argument := state.argument; block := state.block
	state.target = 0; state.argument = 0; state.block = 0
	mut worker := state.worker
	state.worker = unsafe { nil }
	ios_runtime.foundation_thread_count--
	C.ios_objc_initialize_unlock()
	objc_release(target); objc_release(argument); block_release(block)
	objc_pool_free(C.pthread_getspecific(ios_runtime.pool_key))
	C.ios_objc_initialize_lock(); state.finished = true; C.ios_objc_initialize_unlock()
	C.pthread_setspecific(ios_runtime.thread_key, unsafe { nil })
	objc_release(state.object)
	if worker != unsafe { nil } { C.ios_objc_initialize_lock(); worker.done = true; C.ios_objc_initialize_unlock() }
}

fn ns_thread_body(object u64) {
	state := ns_thread_state(object)
	if state.block != 0 { block_invoke_void(state.block); return }
	if state.target == 0 || state.selector == 0 { return }
	imp := native_method(read64(state.target), ctext(state.selector))
	if imp == 0 { panic('iOS: thread target selector has no application implementation') }
	unsafe { ObjAction(voidptr(imp))(state.target, &char(state.selector), state.argument) }
}

// A joinable native worker is retained only by TLS while executing. The small
// join record owns the native handle through all key-destructor iterations.
struct FoundationStart { object u64 worker &FoundationWorker }

fn ns_thread_worker(pointer voidptr) voidptr {
	context := unsafe { &FoundationStart(pointer) }
	object := context.object
	C.free(pointer)
	C.ios_objc_initialize_lock()
	mut state := ns_thread_state(object)
	if C.pthread_setspecific(ios_runtime.thread_key, state) != 0 { panic('iOS: cannot set Foundation worker TLS') }
	ios_runtime.foundation_thread_count++
	state.executing = !state.cancelled
	cancelled := state.cancelled
	C.ios_objc_initialize_unlock()
	if !cancelled {
		imp := native_method(read64(object), 'main')
		if imp == 0 { ns_thread_body(object) }
		else { unsafe { ObjVoid(voidptr(imp))(object, c'main') } }
	}
	return unsafe { nil }
}

fn ns_threads_reap(all bool) {
	for {
		C.ios_objc_initialize_lock()
		mut previous := unsafe { &FoundationWorker(nil) }
		mut worker := ios_runtime.foundation_workers
		for worker != unsafe { nil } && !all && (!worker.done || worker.handle == u64(C.pthread_self())) { previous = worker; worker = worker.next }
		if worker == unsafe { nil } { C.ios_objc_initialize_unlock(); return }
		if previous == unsafe { nil } { ios_runtime.foundation_workers = worker.next }
		else { previous.next = worker.next }
		ios_runtime.foundation_worker_count--
		C.ios_objc_initialize_unlock()
		if darwin_pthread_join(worker.handle, unsafe { nil }) != 0 { panic('iOS: cannot join Foundation thread') }
		C.free(worker)
	}
}

fn ns_thread_start(object u64) {
	ns_threads_reap(false)
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := ns_thread_state(object)
	if !state.initialized || state.started || ios_runtime.threads_stopping { panic('iOS: thread cannot be started') }
	if ios_runtime.foundation_worker_count >= 256 { panic('iOS: Foundation worker limit exceeded') }
	mut worker := unsafe { &FoundationWorker(C.calloc(1, sizeof(FoundationWorker))) }
	context := unsafe { &FoundationStart(C.calloc(1, sizeof(FoundationStart))) }
	if worker == unsafe { nil } || context == unsafe { nil } { panic('iOS: cannot allocate Foundation worker') }
	unsafe { *context = FoundationStart{objc_retain(object), worker} }
	state.started = true
	state.worker = worker
	result := mach_thread_create(unsafe { &worker.handle }, usize(state.stack_size), 0, 16384, 0, unsafe { voidptr(ns_thread_worker) }, context)
	if result != 0 { state.started = false; state.worker = unsafe { nil }; objc_release(object); C.free(context); C.free(worker); panic('iOS: cannot create Foundation worker') }
	worker.next = ios_runtime.foundation_workers
	ios_runtime.foundation_workers = worker
	ios_runtime.foundation_worker_count++
	ios_runtime.foundation_multithreaded = true
}

fn ns_threads_join() {
	C.ios_objc_initialize_lock(); ios_runtime.threads_stopping = true; C.ios_objc_initialize_unlock()
	ns_threads_reap(true)
}

fn ns_threads_stop() {
	// Dispatch/Swift workers are already joined. Foreign pthreads must also
	// have terminated before execute() can unmap their application callbacks.
	pointer := C.pthread_getspecific(ios_runtime.thread_key)
	if ios_runtime.foundation_thread_count != if pointer == unsafe { nil } { 0 } else { 1 } { panic('iOS: Foundation thread is still active at shutdown') }
	ns_thread_cleanup(pointer)
	if ios_runtime.foundation_main_thread != 0 { ns_thread_state(ios_runtime.foundation_main_thread).executing = false }
	objc_release(ios_runtime.foundation_main_thread)
	ios_runtime.foundation_main_thread = 0
	C.pthread_key_delete(ios_runtime.thread_key)
}

fn ns_thread_sleep(seconds f64) {
	if !math.is_finite(seconds) || seconds > 86400 { panic('iOS: thread sleep is outside the finite one-day profile') }
	if seconds <= 0 { return }
	whole := math.floor(seconds)
	mut request := C.timespec{tv_sec: i64(whole), tv_nsec: i64((seconds - whole) * 1e9)}
	mut remaining := C.timespec{}
	for C.nanosleep(unsafe { &request }, unsafe { &remaining }) != 0 {
		if unsafe { *C.ios_errno_address() } != C.EINTR { panic('iOS: thread sleep failed') }
		request = remaining
	}
}

fn ns_thread_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if !ns_thread_matches(object) { return false }
	meta := object in ios_runtime.classes
	if ns_thread_types('NSThread', meta, selector) == none {
		if selector in ['setQualityOfService:', 'qualityOfService', 'setThreadPriority:', 'threadPriority', 'runLoop', 'startAndReturnError:', 'callStackReturnAddresses', 'callStackSymbols', 'isDying'] { panic('iOS: Foundation thread scheduling, run loops and stack introspection are outside the implemented profile') }
		return false
	}
	if meta {
		match selector {
			'currentThread' { frame.x[0] = ns_thread_current() }
			'mainThread' { frame.x[0] = ns_thread_main() }
			'isMainThread' { frame.x[0] = u64(darwin_pthread_main_np() != 0) }
			'isMultiThreaded' { C.ios_objc_initialize_lock(); frame.x[0] = u64(ios_runtime.foundation_multithreaded); C.ios_objc_initialize_unlock() }
			'sleepForTimeInterval:' { ns_thread_sleep(frame_double(&frame, 0)) }
			'sleepUntilDate:' { ns_thread_sleep(if frame.x[2] == 0 { f64(0) } else { cf_date_absolute(frame.x[2]) + 978307200 - f64(dispatch_wall_now_ns()) / 1e9 }) }
			'exit' { if darwin_pthread_main_np() != 0 { panic('iOS: Foundation exit on the main thread is not implemented') }; darwin_pthread_exit(unsafe { nil }) }
			else {
				worker_object := objc_allocate(ios_runtime.names['NSThread'])
				if selector == 'detachNewThreadWithBlock:' { if frame.x[2] == 0 { panic('iOS: nil Foundation thread block') }; ns_thread_initialize(worker_object, 0, 0, 0, frame.x[2]) }
				else { ns_thread_initialize(worker_object, frame.x[3], frame.x[2], frame.x[4], 0) }
				ns_thread_start(worker_object); objc_release(worker_object)
			}
		}
		return true
	}
	if selector.starts_with('init') {
		if selector == 'initWithBlock:' && frame.x[2] == 0 { panic('iOS: nil Foundation thread block') }
		ns_thread_initialize(object, if selector == 'initWithTarget:selector:object:' { frame.x[2] } else { u64(0) }, if selector == 'initWithTarget:selector:object:' { frame.x[3] } else { u64(0) }, if selector == 'initWithTarget:selector:object:' { frame.x[4] } else { u64(0) }, if selector == 'initWithBlock:' { frame.x[2] } else { u64(0) })
		frame.x[0] = object
		return true
	}
	if selector == 'start' { ns_thread_start(object); return true }
	if selector == 'main' { ns_thread_body(object); return true }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := ns_thread_state(object)
	if !state.initialized { panic('iOS: Foundation thread is not initialized') }
	match selector {
		'isExecuting' { frame.x[0] = u64(state.executing) }
		'isFinished' { frame.x[0] = u64(state.finished) }
		'isCancelled' { frame.x[0] = u64(state.cancelled) }
		'isMainThread' { frame.x[0] = u64(state.main) }
		'cancel' { state.cancelled = true }
		'name' { frame.x[0] = objc_retain_autorelease(state.name) }
		'setName:' { value := frame.x[2]; if value != 0 && !objc_is_kind(value, ios_runtime.names['NSString']) { panic('iOS: Foundation thread name requires a string') }; name := if value == 0 { u64(0) } else { owned_string(string_text(value)) }; old := state.name; state.name = name; objc_release(old) }
		'threadDictionary' { if state.dictionary == 0 { state.dictionary = objc_new(ios_runtime.names['NSMutableDictionary']) }; frame.x[0] = state.dictionary }
		'stackSize' { frame.x[0] = state.stack_size }
		'setStackSize:' { size := frame.x[2]; if state.started || size < 16384 || size > 8388608 || size & 16383 != 0 { panic('iOS: Foundation stack requires an unstarted thread and 16 KiB multiples through 8 MiB') }; state.stack_size = size }
		else { return false }
	}
	return true
}
