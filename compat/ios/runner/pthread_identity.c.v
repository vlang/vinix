// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.ios_thread_equal(u64, u64) i32
fn C.pthread_main_np() i32
fn C.pthread_exit(voidptr)

__global pthread_process_main_thread = u64(0)

fn init() {
	// Capture the runner's process thread before app execution, including when
	// an embedding caller later loads an image on a worker. Darwin retains this
	// identity when a worker forks; the fork child does not become its main thread.
	pthread_process_main_thread = u64(C.pthread_self())
}

fn darwin_pthread_equal(first u64, second u64) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	return C.ios_thread_equal(first, second)
}

fn darwin_pthread_main_np() i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	$if macos { return C.pthread_main_np() }
	return C.ios_thread_equal(u64(C.pthread_self()), pthread_process_main_thread)
}

@[noreturn]
fn darwin_pthread_exit(value voidptr) {
	// Native libc runs key destructors and publishes the join result. Every app
	// worker must finish before execute() returns and unmaps its callback code.
	C.pthread_exit(value)
	for {}
}

fn pthread_identity_symbol(symbol string) ?u64 {
	return match symbol {
		'_pthread_equal' { u64(unsafe { voidptr(darwin_pthread_equal) }) }
		'_pthread_main_np' { u64(unsafe { voidptr(darwin_pthread_main_np) }) }
		'_pthread_exit' { u64(unsafe { voidptr(darwin_pthread_exit) }) }
		else { return none }
	}
}
