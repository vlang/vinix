// SPDX-License-Identifier: GPL-2.0-or-later
module main

// One lifetime reference owns the source until cancellation completes. Queue
// work owns a separate reference; external ARC can disappear during a handler.
struct DispatchSource {
mut:
	isa u64
	refs u64 = 2
	external_refs u64 = 1
	queue &DispatchQueue = unsafe { nil }
	suspended u64 = 1
	activated bool
	cancelled bool
	abandoned bool
	finished bool
	finishing bool
	work_pending bool
	context voidptr
	finalizer DispatchFunction = unsafe { nil }
	mask u64
	next u64 = dispatch_forever
	interval u64 = dispatch_forever
	pending u64
	data u64
	event &DispatchSourceHandler = unsafe { nil }
	cancel &DispatchSourceHandler = unsafe { nil }
	updates &DispatchSourceUpdate = unsafe { nil }
	last_update &DispatchSourceUpdate = unsafe { nil }
}

struct DispatchSourceHandler {
mut:
	refs u64 = 1
	block u64
	function DispatchFunction = unsafe { nil }
	context voidptr
	next &DispatchSourceHandler = unsafe { nil }
}

struct DispatchSourceUpdate {
mut:
	handler &DispatchSourceHandler = unsafe { nil }
	cancel bool
	next &DispatchSourceUpdate = unsafe { nil }
}

fn dispatch_source_locked(identity u64) &DispatchSource {
	return dispatch_runtime.sources[identity] or { panic('iOS: invalid dispatch source') }
}

fn darwin_dispatch_source_create(kind u64, handle u64, mask u64, queue_identity u64) u64 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if kind != dispatch_timer_type_address() { panic('iOS: only timer dispatch sources are implemented') }
	if handle != 0 || mask & ~u64(1) != 0 { return 0 }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	if dispatch_runtime.stopping { panic('iOS: dispatch source created during image shutdown') }
	mut source := unsafe { &DispatchSource(C.calloc(1, sizeof(DispatchSource))) }
	if source == unsafe { nil } { panic('iOS: cannot allocate dispatch source') }
	source.isa = dispatch_runtime.source_class
	source.refs = 2
	source.external_refs = 1
	source.suspended = 1
	source.next = dispatch_forever
	source.interval = dispatch_forever
	source.mask = mask
	source.queue = if queue_identity == 0 { dispatch_default_root_locked() } else { dispatch_queue_locked(queue_identity) }
	if !source.queue.immortal { source.queue.refs++ }
	dispatch_runtime.sources[u64(source)] = source
	return u64(source)
}

// The caller frees removed storage after unlocking. No block helpers or app
// finalizers execute inside the scheduler lock.
fn dispatch_source_drop_locked(mut source DispatchSource) bool {
	source.refs--
	if source.refs != 0 { return false }
	if !source.finished || source.work_pending { panic('iOS: dispatch source destroyed while active') }
	dispatch_runtime.sources.delete(u64(&source))
	if !dispatch_runtime.stopping && source.finalizer != unsafe { nil } && source.context != unsafe { nil } {
		dispatch_add_locked(source.queue, 0, 0, source.context, source.finalizer, false)
	}
	dispatch_queue_drop_locked(mut source.queue)
	return true
}

fn dispatch_source_handler_drop_locked(handler &DispatchSourceHandler, head &DispatchSourceHandler) &DispatchSourceHandler {
	if handler == unsafe { nil } { return head }
	mut owned := unsafe { &DispatchSourceHandler(handler) }
	owned.refs--
	if owned.refs != 0 { return head }
	owned.next = head
	return owned
}

fn dispatch_source_handlers_retire(head &DispatchSourceHandler) {
	mut handler := unsafe { &DispatchSourceHandler(head) }
	for handler != unsafe { nil } {
		next := handler.next
		block_release(handler.block)
		C.free(handler)
		handler = next
	}
}

fn dispatch_source_apply_locked(mut source DispatchSource) &DispatchSourceHandler {
	mut retired := unsafe { &DispatchSourceHandler(nil) }
	mut update := source.updates
	unsafe { source.updates = nil; source.last_update = nil }
	for update != unsafe { nil } {
		next := update.next
		if update.handler != unsafe { nil } { update.handler.context = source.context }
		if update.cancel {
			retired = dispatch_source_handler_drop_locked(source.cancel, retired)
			source.cancel = update.handler
		} else {
			retired = dispatch_source_handler_drop_locked(source.event, retired)
			source.event = update.handler
		}
		C.free(update)
		update = next
	}
	return retired
}

fn dispatch_source_due_locked(mut source DispatchSource) {
	if source.cancelled || source.next == dispatch_forever || dispatch_remaining(source.next) != 0 { return }
	mut count := u64(1)
	if source.interval != dispatch_forever {
		count += dispatch_lateness(source.next) / source.interval
	}
	source.pending = if count > ~u64(0) - source.pending { ~u64(0) } else { source.pending + count }
	if source.interval > dispatch_value_limit || count > dispatch_value_limit / source.interval {
		source.next = dispatch_forever
	} else {
		source.next = darwin_dispatch_time(source.next, i64(count * source.interval))
	}
}

fn dispatch_source_schedule_locked(mut source DispatchSource) {
	if dispatch_runtime.stopping || source.finished || !source.activated || source.suspended != 0 || source.work_pending { return }
	if !source.cancelled && source.updates == unsafe { nil } && (source.pending == 0 || source.event == unsafe { nil }) { return }
	source.work_pending = true
	source.refs++
	mut job := dispatch_add_locked(source.queue, 0, 0, &source, dispatch_source_work, false)
	job.cleanup = dispatch_source_work_cleanup
}

fn dispatch_sources_poll_locked() {
	for _, value in dispatch_runtime.sources {
		mut source := value
		if source.activated && source.suspended == 0 && !source.finished {
			dispatch_source_due_locked(mut source)
			dispatch_source_schedule_locked(mut source)
		}
	}
}

fn dispatch_sources_interval_locked() u64 {
	mut interval := dispatch_forever
	for _, source in dispatch_runtime.sources {
		if source.activated && source.suspended == 0 && !source.finished && !source.cancelled
			&& !source.work_pending && source.event != unsafe { nil } {
			remaining := dispatch_remaining(source.next)
			if remaining < interval { interval = remaining }
		}
	}
	return interval
}

fn dispatch_source_work(context voidptr) {
	mut source := unsafe { &DispatchSource(context) }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	if dispatch_runtime.stopping || source.suspended != 0 { C.pthread_mutex_unlock(dispatch_runtime.mutex); return }
	retired := dispatch_source_apply_locked(mut source)
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	dispatch_source_handlers_retire(retired)
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	if dispatch_runtime.stopping || source.suspended != 0 { C.pthread_mutex_unlock(dispatch_runtime.mutex); return }
	dispatch_source_due_locked(mut source)
	cancelling := source.cancelled
	if cancelling { source.finishing = true }
	mut handler := if cancelling { source.cancel } else { source.event }
	if (cancelling && source.abandoned) || (!cancelling && source.pending == 0) { unsafe { handler = nil } }
	if handler != unsafe { nil } { handler.refs++ }
	// Unlike the event function, a cancel function receives the context current
	// when cancellation is delivered, rather than its registration snapshot.
	invocation_context := if handler == unsafe { nil } { unsafe { voidptr(nil) } } else if cancelling { source.context } else { handler.context }
	if !cancelling && handler != unsafe { nil } { source.data = source.pending; source.pending = 0 }
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	if handler != unsafe { nil } {
		if handler.block != 0 { block_invoke_void(handler.block) } else { handler.function(invocation_context) }
	}
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	mut done := dispatch_source_handler_drop_locked(handler, unsafe { nil })
	if cancelling {
		source.finished = true
		done = dispatch_source_handler_drop_locked(source.event, done)
		done = dispatch_source_handler_drop_locked(source.cancel, done)
		unsafe { source.event = nil; source.cancel = nil }
		// The current job still pins the source while capture disposal releases
		// its external owners. Retire the lifetime reference exactly once.
		dispatch_source_drop_locked(mut source)
	}
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	dispatch_source_handlers_retire(done)
}

fn dispatch_source_work_cleanup(context voidptr) {
	mut source := unsafe { &DispatchSource(context) }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	source.work_pending = false
	if !dispatch_runtime.stopping {
		dispatch_source_due_locked(mut source)
		dispatch_source_schedule_locked(mut source)
	}
	removed := dispatch_source_drop_locked(mut source)
	C.pthread_cond_broadcast(dispatch_runtime.condition)
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	if removed { C.free(source) }
	dispatch_retire()
}

fn dispatch_source_set_handler(identity u64, block u64, function DispatchFunction, cancel bool) {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	mut handler := unsafe { &DispatchSourceHandler(nil) }
	if block != 0 || function != unsafe { nil } {
		handler = unsafe { &DispatchSourceHandler(C.calloc(1, sizeof(DispatchSourceHandler))) }
		if handler == unsafe { nil } { panic('iOS: cannot allocate dispatch source handler') }
		handler.refs = 1
		handler.block = block_copy(block)
		handler.function = function
	}
	mut update := unsafe { &DispatchSourceUpdate(C.calloc(1, sizeof(DispatchSourceUpdate))) }
	if update == unsafe { nil } { panic('iOS: cannot allocate dispatch source update') }
	update.handler = handler
	update.cancel = cancel
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	mut source := dispatch_source_locked(identity)
	if dispatch_runtime.stopping || source.finished || source.finishing {
		C.pthread_mutex_unlock(dispatch_runtime.mutex)
		dispatch_source_handlers_retire(handler)
		C.free(update)
		return
	}
	if source.last_update == unsafe { nil } { source.updates = update } else { source.last_update.next = update }
	source.last_update = update
	dispatch_source_schedule_locked(mut source)
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
}

fn darwin_dispatch_source_set_event_handler(identity u64, block u64) { dispatch_source_set_handler(identity, block, unsafe { nil }, false) }
fn darwin_dispatch_source_set_event_handler_f(identity u64, function DispatchFunction) { dispatch_source_set_handler(identity, 0, function, false) }
fn darwin_dispatch_source_set_cancel_handler(identity u64, block u64) { dispatch_source_set_handler(identity, block, unsafe { nil }, true) }
fn darwin_dispatch_source_set_cancel_handler_f(identity u64, function DispatchFunction) { dispatch_source_set_handler(identity, 0, function, true) }

fn darwin_dispatch_source_set_timer(identity u64, start u64, interval u64, leeway u64) {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	mut source := dispatch_source_locked(identity)
	if source.cancelled || dispatch_runtime.stopping { return }
	source.pending = 0
	source.next = if start == 0 { darwin_mach_absolute_time() } else if start == dispatch_wall_now { darwin_dispatch_walltime(unsafe { nil }, 0) } else { start }
	source.interval = if interval == 0 { u64(1) } else { interval }
	// Fire at the requested deadline; no deliberate coalescing delay is needed.
	_ = leeway
	if source.activated { dispatch_workers_start_locked() }
	C.pthread_cond_broadcast(dispatch_runtime.condition)
}

fn darwin_dispatch_source_cancel(identity u64) {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	mut source := dispatch_source_locked(identity)
	source.cancelled = true
	source.pending = 0
	dispatch_source_schedule_locked(mut source)
	C.pthread_cond_broadcast(dispatch_runtime.condition)
}

fn darwin_dispatch_source_testcancel(identity u64) i64 {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	return i64(dispatch_source_locked(identity).cancelled)
}
fn darwin_dispatch_source_get_data(identity u64) u64 {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	return dispatch_source_locked(identity).data
}
fn darwin_dispatch_source_get_handle(identity u64) u64 {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	dispatch_source_locked(identity)
	return 0
}
fn darwin_dispatch_source_get_mask(identity u64) u64 {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	return dispatch_source_locked(identity).mask
}

fn darwin_dispatch_suspend(identity u64) {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	if mut source := dispatch_runtime.sources[identity] { source.suspended++; return }
	mut queue := dispatch_queue_locked(identity)
	if !queue.main && queue.immortal { return }
	queue.suspended++
}
fn darwin_dispatch_resume(identity u64) {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	if mut source := dispatch_runtime.sources[identity] {
		if source.suspended == 0 { panic('iOS: unbalanced dispatch source resume') }
		source.suspended--
		if source.suspended == 0 {
			source.activated = true
			dispatch_source_due_locked(mut source)
			dispatch_source_schedule_locked(mut source)
			dispatch_workers_start_locked()
		}
	} else {
		mut queue := dispatch_queue_locked(identity)
		if !queue.main && queue.immortal { return }
		if queue.suspended == 0 { panic('iOS: unbalanced dispatch queue resume') }
		queue.suspended--
	}
	C.pthread_cond_broadcast(dispatch_runtime.condition)
}

fn darwin_dispatch_set_target_queue(identity u64, target u64) {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	mut destination := if target == 0 { dispatch_default_root_locked() } else { dispatch_queue_locked(target) }
	if mut source := dispatch_runtime.sources[identity] {
		if source.activated { panic('iOS: active dispatch source cannot change target queue') }
		if !destination.immortal { destination.refs++ }
		mut old := source.queue
		source.queue = destination
		dispatch_queue_drop_locked(mut old)
	} else {
		mut queue := dispatch_queue_locked(identity)
		if queue.immortal { C.pthread_mutex_unlock(dispatch_runtime.mutex); return }
		if queue.busy != 0 { panic('iOS: running dispatch queue cannot change target') }
		mut ancestor := destination
		for ancestor != unsafe { nil } {
			if u64(ancestor) == identity { panic('iOS: cyclic dispatch queue target') }
			ancestor = ancestor.target
		}
		if !destination.immortal { destination.refs++ }
		mut old := queue.target
		queue.target = destination
		dispatch_queue_drop_locked(mut old)
	}
	C.pthread_cond_broadcast(dispatch_runtime.condition)
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	dispatch_retire()
}

// Workers and pending jobs retire first. Keep every source registered while
// captured blocks are disposed: a destructor may release another source.
fn dispatch_sources_stop() {
	if dispatch_runtime == unsafe { nil } { return }
	for {
		C.pthread_mutex_lock(dispatch_runtime.mutex)
		mut retired := unsafe { &DispatchSourceHandler(nil) }
		mut found := false
		for _, value in dispatch_runtime.sources {
			mut source := value
			if source.event == unsafe { nil } && source.cancel == unsafe { nil } && source.updates == unsafe { nil } { continue }
			found = true
			retired = dispatch_source_apply_locked(mut source)
			retired = dispatch_source_handler_drop_locked(source.event, retired)
			retired = dispatch_source_handler_drop_locked(source.cancel, retired)
			unsafe { source.event = nil; source.cancel = nil }
			break
		}
		C.pthread_mutex_unlock(dispatch_runtime.mutex)
		if !found { return }
		dispatch_source_handlers_retire(retired)
	}
}

fn dispatch_source_symbol(symbol string) ?u64 {
	return match symbol {
		'_dispatch_source_create' { u64(unsafe { voidptr(darwin_dispatch_source_create) }) }
		'_dispatch_source_set_event_handler' { u64(unsafe { voidptr(darwin_dispatch_source_set_event_handler) }) }
		'_dispatch_source_set_event_handler_f' { u64(unsafe { voidptr(darwin_dispatch_source_set_event_handler_f) }) }
		'_dispatch_source_set_cancel_handler' { u64(unsafe { voidptr(darwin_dispatch_source_set_cancel_handler) }) }
		'_dispatch_source_set_cancel_handler_f' { u64(unsafe { voidptr(darwin_dispatch_source_set_cancel_handler_f) }) }
		'_dispatch_source_set_timer' { u64(unsafe { voidptr(darwin_dispatch_source_set_timer) }) }
		'_dispatch_source_cancel' { u64(unsafe { voidptr(darwin_dispatch_source_cancel) }) }
		'_dispatch_source_testcancel' { u64(unsafe { voidptr(darwin_dispatch_source_testcancel) }) }
		'_dispatch_source_get_data' { u64(unsafe { voidptr(darwin_dispatch_source_get_data) }) }
		'_dispatch_source_get_handle' { u64(unsafe { voidptr(darwin_dispatch_source_get_handle) }) }
		'_dispatch_source_get_mask' { u64(unsafe { voidptr(darwin_dispatch_source_get_mask) }) }
		'_dispatch_suspend' { u64(unsafe { voidptr(darwin_dispatch_suspend) }) }
		'_dispatch_resume' { u64(unsafe { voidptr(darwin_dispatch_resume) }) }
		'_dispatch_set_target_queue' { u64(unsafe { voidptr(darwin_dispatch_set_target_queue) }) }
		else { return none }
	}
}
