// SPDX-License-Identifier: GPL-2.0-or-later
module main

type DispatchFunction = fn (voidptr)

fn C.ios_load_pointer(&u64) u64

fn darwin_dispatch_once_f(predicate &u64, context voidptr, function DispatchFunction) {
	if predicate == unsafe { nil } || function == unsafe { nil } { panic('iOS: invalid dispatch_once arguments') }
	if C.ios_load_pointer(predicate) == ~u64(0) { return }
	C.ios_objc_initialize_lock()
	mut mutex := system_data.dispatch_once[u64(predicate)] or { unsafe { nil } }
	if mutex == unsafe { nil } {
		mutex = C.calloc(1, C.ios_sizeof_mutex())
		if mutex == unsafe { nil } || C.ios_mutex_create(mutex, 1) != 0 { panic('iOS: cannot initialize dispatch_once') }
		system_data.dispatch_once[u64(predicate)] = mutex
	}
	C.ios_objc_initialize_unlock()
	// An error-check mutex diagnoses recursive use of the same predicate.
	// Other predicates and app threads remain independent during the callback.
	if C.pthread_mutex_lock(mutex) != 0 { panic('iOS: recursive dispatch_once invocation') }
	defer { C.pthread_mutex_unlock(mutex) }
	if C.ios_load_pointer(predicate) != ~u64(0) {
		function(context)
		C.ios_store_pointer(predicate, ~u64(0))
	}
}

fn dispatch_block(context voidptr) { block_invoke_void(u64(context)) }
fn darwin_dispatch_once(predicate &u64, block u64) { darwin_dispatch_once_f(predicate, unsafe { voidptr(block) }, dispatch_block) }

fn darwin_dispatch_get_main_queue() u64 { return u64(unsafe { &system_data.main_queue[0] }) }

fn darwin_dispatch_async(queue u64, block u64) {
	dispatch_submit(queue, 0, block, unsafe { nil }, unsafe { nil })
}

fn darwin_dispatch_async_f(queue u64, context voidptr, function DispatchFunction) {
	dispatch_submit(queue, 0, 0, context, function)
}

fn darwin_dispatch_after(when u64, queue u64, block u64) {
	dispatch_submit(queue, when, block, unsafe { nil }, unsafe { nil })
}

fn darwin_dispatch_after_f(when u64, queue u64, context voidptr, function DispatchFunction) {
	dispatch_submit(queue, when, 0, context, function)
}

fn darwin_dispatch_sync(queue u64, block u64) { dispatch_sync(queue, block, unsafe { nil }, unsafe { nil }) }
fn darwin_dispatch_sync_f(queue u64, context voidptr, function DispatchFunction) { dispatch_sync(queue, 0, context, function) }

fn dispatch_symbol(symbol string) ?u64 {
	return match symbol {
		'_dispatch_once_f' { u64(unsafe { voidptr(darwin_dispatch_once_f) }) }
		'_dispatch_once' { u64(unsafe { voidptr(darwin_dispatch_once) }) }
		'_dispatch_async' { u64(unsafe { voidptr(darwin_dispatch_async) }) }
		'_dispatch_async_f' { u64(unsafe { voidptr(darwin_dispatch_async_f) }) }
		'_dispatch_after' { u64(unsafe { voidptr(darwin_dispatch_after) }) }
		'_dispatch_after_f' { u64(unsafe { voidptr(darwin_dispatch_after_f) }) }
		'_dispatch_sync' { u64(unsafe { voidptr(darwin_dispatch_sync) }) }
		'_dispatch_sync_f' { u64(unsafe { voidptr(darwin_dispatch_sync_f) }) }
		'_dispatch_time' { u64(unsafe { voidptr(darwin_dispatch_time) }) }
		'_dispatch_walltime' { u64(unsafe { voidptr(darwin_dispatch_walltime) }) }
		'_dispatch_get_main_queue' { u64(unsafe { voidptr(darwin_dispatch_get_main_queue) }) }
		'_dispatch_get_global_queue' { u64(unsafe { voidptr(darwin_dispatch_get_global_queue) }) }
		'_dispatch_queue_create' { u64(unsafe { voidptr(darwin_dispatch_queue_create) }) }
		'_dispatch_queue_create_with_target\$V2' { u64(unsafe { voidptr(darwin_dispatch_queue_create_with_target) }) }
		'_dispatch_queue_get_label' { u64(unsafe { voidptr(darwin_dispatch_queue_get_label) }) }
		'_dispatch_retain' { u64(unsafe { voidptr(darwin_dispatch_retain) }) }
		'_dispatch_release' { u64(unsafe { voidptr(darwin_dispatch_release) }) }
		'_dispatch_set_context' { u64(unsafe { voidptr(darwin_dispatch_set_context) }) }
		'_dispatch_get_context' { u64(unsafe { voidptr(darwin_dispatch_get_context) }) }
		'_dispatch_set_finalizer_f' { u64(unsafe { voidptr(darwin_dispatch_set_finalizer_f) }) }
		else { return none }
	}
}
