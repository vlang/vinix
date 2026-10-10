// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.ios_atfork_lock()
fn C.ios_atfork_unlock()
fn C.ios_atfork_phase() i32
fn C.ios_atfork_set_phase(i32)
fn C.ios_atfork_install(voidptr, voidptr, voidptr) i32
fn C.ios_fork() i32
fn C.ios_waitpid(i32, &i32, i32) i32
fn C.ios_wait_status(i32, &i32)

struct ImageForkHandler {
mut:
	previous &ImageForkHandler = unsafe { nil }
	next &ImageForkHandler = unsafe { nil }
	prepare ImageExit = unsafe { nil }
	parent ImageExit = unsafe { nil }
	child ImageExit = unsafe { nil }
}

struct ImageForkState {
mut:
	installed bool
	active bool
	head &ImageForkHandler = unsafe { nil }
	tail &ImageForkHandler = unsafe { nil }
}

// The native dispatcher registration lives for the process. Image callbacks
// belong only to the current execution and are freed before any module unmaps.
__global image_fork_state = ImageForkState{}

fn image_atfork_start() ! {
	C.ios_atfork_lock()
	defer { C.ios_atfork_unlock() }
	if image_fork_state.active { return error('iOS: fork handlers already active') }
	if !image_fork_state.installed {
		if C.ios_atfork_install(unsafe { voidptr(image_atfork_prepare) },
			unsafe { voidptr(image_atfork_parent) }, unsafe { voidptr(image_atfork_child) }) != 0 {
			return error('iOS: cannot install native fork dispatchers')
		}
		image_fork_state.installed = true
	}
	image_fork_state.active = true
}

fn image_atfork_prepare() {
	// Hold the registry through all three phases. This pins the mapped code,
	// serializes concurrent forks and prevents a registration lock being left
	// owned by a vanished thread in the child. No allocation occurs here.
	C.ios_atfork_lock()
	C.ios_atfork_set_phase(1)
	mut handler := image_fork_state.tail
	for handler != unsafe { nil } {
		if handler.prepare != unsafe { nil } { handler.prepare() }
		handler = handler.previous
	}
	// Pin the native-thread namespace across the actual fork. A normal native
	// mutex can be released by the surviving caller in either process.
	C.ios_mach_threads_lock()
	mach_threads_fork_prepare()
}

fn image_atfork_complete(child bool) {
	if child { mach_threads_fork_child() } else { mach_threads_fork_parent() }
	C.ios_mach_threads_unlock()
	mut handler := image_fork_state.head
	for handler != unsafe { nil } {
		callback := if child { handler.child } else { handler.parent }
		if callback != unsafe { nil } { callback() }
		handler = handler.next
	}
	C.ios_atfork_set_phase(0)
	C.ios_atfork_unlock()
}

fn image_atfork_parent() { image_atfork_complete(false) }
fn image_atfork_child() { image_atfork_complete(true) }

fn darwin_pthread_atfork(prepare ImageExit, parent ImageExit, child ImageExit) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	// Callback registration during dispatch would relock the pinned registry.
	// Reject it explicitly, rather than hanging the fork or returning success.
	if C.ios_atfork_phase() != 0 { return 11 } // Darwin EDEADLK
	C.ios_atfork_lock()
	defer { C.ios_atfork_unlock() }
	if !image_fork_state.active { return 22 }
	if prepare == unsafe { nil } && parent == unsafe { nil } && child == unsafe { nil } { return 0 }
	mut handler := unsafe { &ImageForkHandler(C.calloc(1, sizeof(ImageForkHandler))) }
	if handler == unsafe { nil } { return 12 }
	unsafe { *handler = ImageForkHandler{previous: image_fork_state.tail,
		prepare: prepare, parent: parent, child: child} }
	if image_fork_state.tail == unsafe { nil } { image_fork_state.head = handler }
	else { image_fork_state.tail.next = handler }
	image_fork_state.tail = handler
	return 0
}

fn image_atfork_stop() {
	// Acquiring the same lock waits for every in-flight callback. Destructors
	// have already run, so they can still register/fork before this boundary.
	C.ios_atfork_lock()
	defer { C.ios_atfork_unlock() }
	image_fork_state.active = false
	mut handler := image_fork_state.head
	image_fork_state.head = unsafe { nil }
	image_fork_state.tail = unsafe { nil }
	for handler != unsafe { nil } {
		next := handler.next
		C.free(handler)
		handler = next
	}
}

fn darwin_fork() i32 {
	previous := unsafe { *C.ios_errno_address() }
	return darwin_process_result(C.ios_fork(), previous)
}

fn wait_signal_darwin(signal i32) i32 {
	$if linux {
		return match signal {
			7 { 10 } // SIGBUS
			10 { 30 } // SIGUSR1
			12 { 31 } // SIGUSR2
			17 { 20 } // SIGCHLD
			18 { 19 } // SIGCONT
			19 { 17 } // SIGSTOP
			20 { 18 } // SIGTSTP
			23 { 16 } // SIGURG
			29 { 23 } // SIGIO
			31 { 12 } // SIGSYS
			else { signal }
		}
	}
	return signal
}

fn darwin_waitpid(pid i32, output &i32, options i32) i32 {
	if options & ~i32(0x13) != 0 { darwin_set_errno(22); return -1 }
	mut flags := i32(0)
	if options & 1 != 0 { flags |= i32(C.WNOHANG) }
	if options & 2 != 0 { flags |= i32(C.WUNTRACED) }
	if options & 0x10 != 0 { flags |= i32(C.WCONTINUED) }
	previous := unsafe { *C.ios_errno_address() }
	mut native_status := i32(0)
	result := C.ios_waitpid(pid, unsafe { &native_status }, flags)
	if result > 0 && output != unsafe { nil } {
		mut fields := [3]i32{}
		C.ios_wait_status(native_status, unsafe { &fields[0] })
		status := match fields[0] {
			1 { fields[1] << 8 }
			2 { wait_signal_darwin(fields[1]) | if fields[2] != 0 { i32(0x80) } else { i32(0) } }
			3 { (wait_signal_darwin(fields[1]) << 8) | 0x7f }
			4 { i32(0x137f) } // Darwin continued status
			else { native_status }
		}
		unsafe { *output = status }
	}
	return darwin_process_result(result, previous)
}
