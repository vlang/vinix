// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Foundation stores one borrowed C function pointer for the process. This is
// registration only: throwing/unwinding through Mach-O frames is unsupported.
fn ns_set_uncaught_handler_checked(handler u64) bool {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return false }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	ios_runtime.uncaught_exception_handler = handler
	return true
}

fn ns_set_uncaught_handler(handler u64) {
	if !ns_set_uncaught_handler_checked(handler) { panic('iOS: exception handler registration outside the runtime lifetime') }
}

fn ns_get_uncaught_handler() u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return 0 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	return ios_runtime.uncaught_exception_handler
}

fn ns_uncaught_handler_stop() {
	// All application workers and teardown callbacks have drained. Forget the
	// borrowed address before the loader unmaps its owning application image.
	C.ios_objc_initialize_lock()
	ios_runtime.uncaught_exception_handler = 0
	C.ios_objc_initialize_unlock()
}
