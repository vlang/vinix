// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos { fn C.thread_resume(u32) i32 }

fn darwin_thread_resume(name u32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.ios_mach_threads_lock()
	result := thread_exception_destination(name)
	C.ios_mach_threads_unlock()
	if result != 0 { return result }
	$if macos { return C.thread_resume(name) }
	// Vinix cannot suspend individual Mach threads yet, so every live thread
	// has a zero user suspension count. Native resume rejects this underflow
	// with KERN_FAILURE; it must not report success or send process-wide SIGCONT.
	return 5
}
