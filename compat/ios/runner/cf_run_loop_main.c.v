// SPDX-License-Identifier: GPL-2.0-or-later
module main

// One borrowed main-loop handle, shared with Foundation and the existing
// desktop scheduler. The runtime owns its sole cached reference until stop.
// Workers may retrieve it without creating a loop for their own thread.
fn cf_run_loop_get_main() u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		panic('iOS: main run loop outside runtime lifetime')
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.run_loop == 0 {
		ios_runtime.run_loop = objc_allocate(ios_runtime.names['NSRunLoop'])
		obj_header(ios_runtime.run_loop).valid = true
	}
	return ios_runtime.run_loop
}

// Background handles belong to the current Foundation thread's TLS lifetime,
// not its pthread identifier (which the host may reuse after thread exit).
// Handle lookup does not start a loop or dispatch any callbacks.
fn cf_run_loop_get_current() u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		panic('iOS: current run loop outside runtime lifetime')
	}
	if u64(C.pthread_self()) == ios_runtime.main_thread { return cf_run_loop_get_main() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := ns_thread_state(ns_thread_current())
	if state.run_loop == 0 {
		state.run_loop = objc_allocate(ios_runtime.names['NSRunLoop'])
		obj_header(state.run_loop).valid = true
	}
	return state.run_loop
}

fn ns_run_loop_types(name string, meta bool, selector string) ?string {
	if name != 'NSRunLoop' { return none }
	if meta { return if selector in ['mainRunLoop', 'currentRunLoop']! { ?string('@16@0:8') } else { none } }
	return if selector == 'getCFRunLoop' { ?string('^{__CFRunLoop=}16@0:8') } else { none }
}

fn ns_run_loop_selector(object u64, selector string) bool {
	if object !in ios_runtime.classes {
		return selector == 'getCFRunLoop' && objc_is_kind(object, ios_runtime.names['NSRunLoop'])
	}
	if selector !in ['mainRunLoop', 'currentRunLoop']! { return false }
	mut cls := object
	for _ in 0 .. 128 {
		if cls == ios_runtime.names['NSRunLoop'] { return true }
		info := ios_runtime.classes[cls] or { return false }
		cls = info.parent
		if cls == 0 { return false }
	}
	panic('iOS: cyclic run-loop superclass chain')
}

fn ns_run_loop_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if !ns_run_loop_selector(object, selector) { return false }
	match selector {
		'mainRunLoop' { frame.x[0] = cf_run_loop_get_main() }
		'currentRunLoop' { frame.x[0] = cf_run_loop_get_current() }
		else {
			if !obj_header(object).valid { panic('iOS: NSRunLoop has no thread-owned handle') }
			frame.x[0] = object
		}
	}
	return true
}
