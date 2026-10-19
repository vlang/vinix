// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos { fn C.thread_suspend(u32) i32 }

fn darwin_thread_suspend(name u32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.ios_mach_threads_lock()
	result := thread_exception_destination(name)
	C.ios_mach_threads_unlock()
	if result != 0 { return result }
	// Self-suspension waits for a different thread to resume us. Never hold
	// the shared namespace lock across that native Mach call.
	$if macos { return C.thread_suspend(name) }
	// Vinix has no individual-thread suspension backend. Process-wide
	// SIGSTOP, a bookkeeping-only count or a successful no-op cannot supply it.
	return 46 // KERN_NOT_SUPPORTED
}
