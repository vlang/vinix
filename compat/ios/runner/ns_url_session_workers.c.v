// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Blocking transfers must not occupy dispatch's callback workers. This private
// executor owns accepted contexts until cleanup and supplies a cancellation cell
// borrowed only for run(). Task/request state belongs to the caller's context.
enum URLSessionWorkerOutcome { completed cancelled rejected stopped }
type URLSessionWorkerRun = fn (voidptr, &u64)
type URLSessionWorkerCleanup = fn (voidptr, URLSessionWorkerOutcome)

struct URLSessionWorkerJob {
	identity u64
	context voidptr
	run URLSessionWorkerRun
	cleanup URLSessionWorkerCleanup
mut:
	cancel u64
	retiring bool
}

struct URLSessionWorkerArgument {
mut:
	state &URLSessionWorkers = unsafe { nil }
	slot int
}

@[heap]
struct URLSessionWorkers {
mut:
	mutex voidptr
	condition voidptr
	threads [4]usize
	arguments [4]URLSessionWorkerArgument
	thread_count int
	queue [64]&URLSessionWorkerJob
	head int
	count int
	running [4]&URLSessionWorkerJob
	stopping bool
	joined bool
}

__global url_session_workers = unsafe { &URLSessionWorkers(nil) }
// IDs and this one native TLS key outlive an image/runtime. A late cancellation
// cannot alias a job from a later runtime, and cleanup retains its shutdown guard
// even when an already-retired executor rejects a new submission.
__global url_session_worker_sequence = u64(0)
__global url_session_worker_key = u64(0)
__global url_session_worker_key_ready = false

fn url_session_worker_enter() voidptr {
	C.ios_objc_initialize_lock()
	if !url_session_worker_key_ready {
		if C.ios_key_create(unsafe { &url_session_worker_key }, unsafe { nil }) != 0 { panic('iOS: cannot initialize URL session worker TLS') }
		url_session_worker_key_ready = true
	}
	key := url_session_worker_key
	C.ios_objc_initialize_unlock()
	previous := C.pthread_getspecific(key)
	if C.pthread_setspecific(key, unsafe { voidptr(1) }) != 0 { panic('iOS: cannot enter URL session worker callback') }
	return previous
}

fn url_session_worker_leave(previous voidptr) {
	if C.pthread_setspecific(url_session_worker_key, previous) != 0 { panic('iOS: cannot leave URL session worker callback') }
}

fn url_session_worker_retire(context voidptr, cleanup URLSessionWorkerCleanup, outcome URLSessionWorkerOutcome) {
	previous := url_session_worker_enter()
	pool := objc_pool_push()
	cleanup(context, outcome)
	objc_pool_pop(pool)
	url_session_worker_leave(previous)
}

// Called under the runtime lock; only native allocations/thread startup occur.
fn url_session_workers_new() &URLSessionWorkers {
	mut state := unsafe { &URLSessionWorkers(C.calloc(1, sizeof(URLSessionWorkers))) }
	if state == unsafe { nil } { panic('iOS: cannot allocate URL session workers') }
	state.mutex = C.calloc(1, C.ios_sizeof_mutex())
	state.condition = C.calloc(1, C.ios_sizeof_cond())
	if state.mutex == unsafe { nil } || state.condition == unsafe { nil }
		|| C.ios_mutex_create(state.mutex, 0) != 0 || C.pthread_cond_init(state.condition, unsafe { nil }) != 0 {
		panic('iOS: cannot initialize URL session workers')
	}
	for slot in 0 .. 4 { state.arguments[slot] = URLSessionWorkerArgument{state: state, slot: slot} }
	for slot in 0 .. 4 {
		if darwin_pthread_create(unsafe { &state.threads[slot] }, unsafe { nil }, unsafe { voidptr(url_session_worker_main) },
			unsafe { &state.arguments[slot] }) != 0 { panic('iOS: cannot start URL session worker') }
		state.thread_count++
	}
	return state
}

// Every path consumes the context exactly once, including capacity rejection
// and shutdown. Cleanup runs without either scheduler/state lock and receives
// an autorelease pool, including when rejection is synchronous on the caller.
fn url_session_workers_submit(context voidptr, run URLSessionWorkerRun, cleanup URLSessionWorkerCleanup) u64 {
	if run == unsafe { nil } || cleanup == unsafe { nil } { panic('iOS: URL session work requires run and cleanup') }
	C.ios_objc_initialize_lock()
	if ios_runtime == unsafe { nil } || system_data == unsafe { nil } { panic('iOS: URL session workers require an initialized runtime') }
	if ios_runtime.url_session_workers_stopping {
		C.ios_objc_initialize_unlock()
		url_session_worker_retire(context, cleanup, .stopped)
		return 0
	}
	if url_session_workers == unsafe { nil } { url_session_workers = url_session_workers_new() }
	mut state := url_session_workers
	C.pthread_mutex_lock(state.mutex)
	if state.count == state.queue.len || url_session_worker_sequence == ~u64(0) {
		C.pthread_mutex_unlock(state.mutex); C.ios_objc_initialize_unlock()
		url_session_worker_retire(context, cleanup, .rejected)
		return 0
	}
	mut job := unsafe { &URLSessionWorkerJob(C.calloc(1, sizeof(URLSessionWorkerJob))) }
	if job == unsafe { nil } { panic('iOS: cannot allocate URL session work') }
	url_session_worker_sequence++
	identity := url_session_worker_sequence
	unsafe { *job = URLSessionWorkerJob{identity: identity, context: context, run: run, cleanup: cleanup} }
	state.queue[(state.head + state.count) % state.queue.len] = job
	state.count++
	C.pthread_cond_signal(state.condition)
	C.pthread_mutex_unlock(state.mutex)
	C.ios_objc_initialize_unlock()
	return identity
}

fn url_session_workers_cancel(identity u64) bool {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	state := url_session_workers
	if state == unsafe { nil } { return false }
	C.pthread_mutex_lock(state.mutex)
	defer { C.pthread_mutex_unlock(state.mutex) }
	for slot in 0 .. state.count {
		job := state.queue[(state.head + slot) % state.queue.len]
		if job.identity == identity { C.ios_store_pointer(unsafe { &job.cancel }, 1); return true }
	}
	for job in state.running {
		if job != unsafe { nil } && !job.retiring && job.identity == identity {
			C.ios_store_pointer(unsafe { &job.cancel }, 1)
			return true
		}
	}
	return false
}

fn url_session_worker_main(argument voidptr) voidptr {
	args := unsafe { &URLSessionWorkerArgument(argument) }
	mut state := args.state
	slot := args.slot
	for {
		C.pthread_mutex_lock(state.mutex)
		for state.count == 0 && !state.stopping { C.pthread_cond_wait(state.condition, state.mutex) }
		if state.stopping { C.pthread_mutex_unlock(state.mutex); return unsafe { nil } }
		mut job := state.queue[state.head]
		state.queue[state.head] = unsafe { nil }
		state.head = (state.head + 1) % state.queue.len
		state.count--
		state.running[slot] = job
		C.pthread_mutex_unlock(state.mutex)
		previous := url_session_worker_enter()
		pool := objc_pool_push()
		ran := !data_http_cancelled(unsafe { &job.cancel })
		if ran { job.run(job.context, unsafe { &job.cancel }) }
		C.pthread_mutex_lock(state.mutex)
		job.retiring = true
		outcome := if state.stopping { URLSessionWorkerOutcome.stopped } else if ran { URLSessionWorkerOutcome.completed } else { URLSessionWorkerOutcome.cancelled }
		C.pthread_mutex_unlock(state.mutex)
		job.cleanup(job.context, outcome)
		objc_pool_pop(pool)
		url_session_worker_leave(previous)
		C.pthread_mutex_lock(state.mutex)
		state.running[slot] = unsafe { nil }
		C.pthread_mutex_unlock(state.mutex)
		C.free(job)
	}
	return unsafe { nil }
}

fn url_session_workers_stop() {
	C.ios_objc_initialize_lock()
	if url_session_worker_key_ready && C.pthread_getspecific(url_session_worker_key) != unsafe { nil } {
		panic('iOS: runtime shutdown inside URL session work or cleanup is not implemented')
	}
	ios_runtime.url_session_workers_stopping = true
	mut state := url_session_workers
	if state == unsafe { nil } || state.joined { C.ios_objc_initialize_unlock(); return }
	if u64(C.pthread_self()) != ios_runtime.main_thread { panic('iOS: URL session worker shutdown requires the main thread') }
	C.pthread_mutex_lock(state.mutex)
	state.stopping = true
	for job in state.running { if job != unsafe { nil } { C.ios_store_pointer(unsafe { &job.cancel }, 1) } }
	C.pthread_cond_broadcast(state.condition)
	C.pthread_mutex_unlock(state.mutex)
	C.ios_objc_initialize_unlock()
	// Cancellation remains owned by each worker's socket path; the stopping
	// thread never closes another thread's file descriptor.
	for slot in 0 .. state.thread_count {
		if darwin_pthread_join(u64(state.threads[slot]), unsafe { nil }) != 0 { panic('iOS: cannot join URL session worker') }
	}
	for {
		C.pthread_mutex_lock(state.mutex)
		if state.count == 0 { C.pthread_mutex_unlock(state.mutex); break }
		job := state.queue[state.head]
		state.queue[state.head] = unsafe { nil }
		state.head = (state.head + 1) % state.queue.len
		state.count--
		C.pthread_mutex_unlock(state.mutex)
		url_session_worker_retire(job.context, job.cleanup, .stopped)
		C.free(job)
	}
	C.ios_objc_initialize_lock()
	state.thread_count = 0
	state.joined = true
	C.ios_objc_initialize_unlock()
}

fn url_session_workers_free() {
	url_session_workers_stop()
	C.ios_objc_initialize_lock()
	state := url_session_workers
	url_session_workers = unsafe { nil }
	C.ios_objc_initialize_unlock()
	if state == unsafe { nil } { return }
	C.pthread_cond_destroy(state.condition); C.pthread_mutex_destroy(state.mutex)
	C.free(state.condition); C.free(state.mutex); C.free(state)
}
