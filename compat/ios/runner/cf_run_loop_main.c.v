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
	}
	return ios_runtime.run_loop
}
