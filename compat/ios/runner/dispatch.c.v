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

fn dispatch_symbol(symbol string) ?u64 {
	return match symbol {
		'_dispatch_once_f' { u64(unsafe { voidptr(darwin_dispatch_once_f) }) }
		'_dispatch_once' { u64(unsafe { voidptr(darwin_dispatch_once) }) }
		else { return none }
	}
}
