// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.ios_mach_threads_lock()
fn C.ios_mach_threads_unlock()
$if linux {
	fn C.ios_thread_lifetime_init(voidptr) i32
	fn C.ios_thread_lifetime_status(voidptr) i32
}
$if macos {
	fn C.ios_native_thread_port(u64) u32
	fn C.ios_native_port_thread(u32) u64
	fn C.ios_native_thread_self() u32
	fn C.ios_native_port_type(u32, &u32) i32
	fn C.ios_native_port_refs(u32, i32, &u32) i32
	fn C.ios_native_port_mod_refs(u32, i32, i32) i32
	fn C.ios_native_port_deallocate(u32) i32
}

type MachThreadStart = fn (voidptr) voidptr

struct MachThreadPort {
mut:
	next &MachThreadPort = unsafe { nil }
	name u32
	handle u64
	lifetime voidptr
	start MachThreadStart = unsafe { nil }
	argument voidptr
	started bool
	fork_unlocked bool
	refs u32
	borrowed bool
	dead bool
}

// Never reuse a name across image executions, even if native pthread handles
// are recycled. Exhaustion returns MACH_PORT_NULL instead of aliasing a port.
__global mach_thread_next_name = u64(0x103)

fn mach_thread_retire(mut port MachThreadPort) {
	port.handle = 0
	port.dead = true
	if port.borrowed && port.refs > 0 && port.refs != 65535 { port.refs-- }
	port.borrowed = false
}

// Caller holds the namespace lock. A native robust mutex tracks this specific
// thread's lifetime, including all native key-destructor iterations. Its owner
// death is independent of recycled thread IDs and freed native pthread objects.
// Owned send references become dead-name references when the kernel thread
// terminates. No notification request is registered that would add a reference.
fn mach_threads_refresh() {
	mut previous := unsafe { &MachThreadPort(nil) }
	mut port := system_data.thread_ports
	for port != unsafe { nil } {
		next := port.next
		$if linux {
			if port.started && !port.dead {
				status := C.ios_thread_lifetime_status(port.lifetime)
				if status == C.EOWNERDEAD || status == C.ENOTRECOVERABLE { mach_thread_retire(mut port) }
				else if status != C.EBUSY { panic('iOS: invalid native thread lifetime') }
			}
		}
		if port.dead && port.lifetime != unsafe { nil } {
			if C.pthread_mutex_destroy(port.lifetime) != 0 { panic('iOS: active thread lifetime at retirement') }
			C.free(port.lifetime)
			port.lifetime = unsafe { nil }
		}
		if port.dead && port.refs == 0 {
			if previous == unsafe { nil } { system_data.thread_ports = next }
			else { previous.next = next }
			C.free(port)
		} else { previous = port }
		port = next
	}
}

fn mach_thread_find(name u32) &MachThreadPort {
	mut port := system_data.thread_ports
	for port != unsafe { nil } {
		if port.name == name && port.refs != 0 { return port }
		port = port.next
	}
	return unsafe { nil }
}

// Caller holds the namespace lock. Every adapter-created thread has one
// borrowed port and an independent native lifetime object before it can run.
fn mach_thread_new(handle u64) ?&MachThreadPort {
	if mach_thread_next_name >= 0xffffffff { return none }
	mut port := unsafe { &MachThreadPort(C.calloc(1, sizeof(MachThreadPort))) }
	if port == unsafe { nil } { return none }
	unsafe { *port = MachThreadPort{name: u32(mach_thread_next_name), handle: handle, refs: 1, borrowed: true} }
	$if linux {
		port.lifetime = C.calloc(1, C.ios_sizeof_mutex())
		if port.lifetime == unsafe { nil } { C.free(port); return none }
		if C.ios_thread_lifetime_init(port.lifetime) != 0 { C.free(port.lifetime); C.free(port); return none }
	}
	mach_thread_next_name += 0x100
	return port
}

fn mach_thread_start(context voidptr) voidptr {
	mut port := unsafe { &MachThreadPort(context) }
	if C.pthread_mutex_lock(port.lifetime) != 0 { panic('iOS: cannot hold native thread lifetime') }
	C.ios_mach_threads_lock()
	port.started = true
	start := port.start
	argument := port.argument
	port.start = unsafe { nil }
	port.argument = unsafe { nil }
	C.ios_mach_threads_unlock()
	// Leave the robust mutex owned. Native libc releases it after all key
	// destructors on normal return and on an explicit native pthread_exit.
	return start(argument)
}

fn mach_thread_create(output voidptr, size usize, top u64, guard usize, detached i32, start voidptr, argument voidptr) i32 {
	$if linux {
		C.ios_mach_threads_lock()
		defer { C.ios_mach_threads_unlock() }
		mach_threads_refresh()
		mut port := mach_thread_new(0) or { return 12 }
		port.start = unsafe { MachThreadStart(start) }
		port.argument = argument
		result := C.ios_thread_create(output, size, top, guard, detached, unsafe { voidptr(mach_thread_start) }, port)
		if result != 0 {
			if C.pthread_mutex_destroy(port.lifetime) != 0 { panic('iOS: active thread lifetime after failed create') }
			C.free(port.lifetime)
			C.free(port)
			return result
		}
		port.handle = read64(u64(output))
		port.next = system_data.thread_ports
		system_data.thread_ports = port
		return 0
	}
	return C.ios_thread_create(output, size, top, guard, detached, start, argument)
}

fn mach_threads_join_begin(handle u64) u32 {
	$if linux {
		C.ios_mach_threads_lock()
		defer { C.ios_mach_threads_unlock() }
		mut port := system_data.thread_ports
		for port != unsafe { nil } {
			if port.handle == handle { return port.name }
			port = port.next
		}
	}
	return 0
}

fn mach_threads_join_end(name u32) {
	$if linux {
		if name == 0 { return }
		C.ios_mach_threads_lock()
		defer { C.ios_mach_threads_unlock() }
		mut port := mach_thread_find(name)
		if port != unsafe { nil } { mach_thread_retire(mut port) }
		mach_threads_refresh()
	}
}

// Remove the caller's robust mutex from its native list before fork. Its
// owner TID changes in the child, so inheriting that locked object is invalid.
// The namespace lock stays held across fork; the parent restores ownership.
fn mach_threads_fork_prepare() {
	$if linux {
		if system_data == unsafe { nil } { return }
		mut port := system_data.thread_ports
		for port != unsafe { nil } {
			if port.handle == u64(C.pthread_self()) && port.started && !port.dead {
				if C.pthread_mutex_unlock(port.lifetime) != 0 { panic('iOS: cannot release thread lifetime before fork') }
				port.fork_unlocked = true
			}
			port = port.next
		}
	}
}

fn mach_threads_fork_parent() {
	$if linux {
		if system_data == unsafe { nil } { return }
		mut port := system_data.thread_ports
		for port != unsafe { nil } {
			if port.fork_unlocked {
				if C.pthread_mutex_lock(port.lifetime) != 0 { panic('iOS: cannot restore thread lifetime after fork') }
				port.fork_unlocked = false
			}
			port = port.next
		}
	}
}

// Other threads vanished in the child. Its surviving thread obtains a new
// namespace/lifetime on its next self query. Caller holds the namespace lock.
fn mach_threads_fork_child() {
	mach_threads_clear(true)
}

fn mach_threads_clear(forked bool) {
	if system_data == unsafe { nil } { return }
	mut port := system_data.thread_ports
	system_data.thread_ports = unsafe { nil }
	for port != unsafe { nil } {
		next := port.next
		if port.lifetime != unsafe { nil } {
			if !forked {
				if !port.dead && port.handle == u64(C.pthread_self()) {
					if C.pthread_mutex_unlock(port.lifetime) != 0 { panic('iOS: cannot release entry thread lifetime') }
				} else if !port.dead { panic('iOS: active thread at image shutdown') }
				if C.pthread_mutex_destroy(port.lifetime) != 0 { panic('iOS: active thread at image shutdown') }
			}
			// Fork removed the caller's node from its robust list in prepare;
			// no surviving thread can access the other inherited mutexes.
			C.free(port.lifetime)
		}
		C.free(port)
		port = next
	}
}

fn mach_threads_stop() {
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	mach_threads_refresh()
	mach_threads_clear(false)
}

// Requires a valid native pthread handle, exactly like the native API. The
// returned right is borrowed; repeated queries do not increase its references.
fn darwin_pthread_mach_thread_np(handle u64) u32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if handle == 0 { return 0 }
	$if macos { return C.ios_native_thread_port(handle) }
	$if linux {
		C.ios_mach_threads_lock()
		defer { C.ios_mach_threads_unlock() }
		mach_threads_refresh()
		mut port := system_data.thread_ports
		for port != unsafe { nil } {
			if port.handle == handle { return port.name }
			port = port.next
		}
		// Native callbacks and the entry thread can register themselves safely.
		// A foreign, unregistered remote pthread cannot be instrumented here.
		if handle != u64(C.pthread_self()) { return 0 }
		port = mach_thread_new(handle) or { return 0 }
		if C.pthread_mutex_lock(port.lifetime) != 0 { panic('iOS: cannot hold entry thread lifetime') }
		port.started = true
		port.next = system_data.thread_ports
		system_data.thread_ports = port
		return port.name
	}
	return 0
}

fn darwin_pthread_from_mach_thread_np(name u32) u64 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	$if macos { return C.ios_native_port_thread(name) }
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	mach_threads_refresh()
	port := mach_thread_find(name)
	return if port == unsafe { nil } { u64(0) } else { port.handle }
}

fn darwin_mach_thread_self() u32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	$if macos { return C.ios_native_thread_self() }
	name := darwin_pthread_mach_thread_np(u64(C.pthread_self()))
	if name == 0 { return 0 }
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	mut port := mach_thread_find(name)
	if port == unsafe { nil } { return 0 }
	if port.refs != 65535 { port.refs++ }
	return name
}

fn darwin_mach_port_type(task u32, name u32, output &u32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if task != system_data.task_self || output == unsafe { nil } { return 4 }
	$if macos { return C.ios_native_port_type(name, output) }
	if name == 0xffffffff { unsafe { *output = 0x100000 }; return 0 }
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	mach_threads_refresh()
	port := mach_thread_find(name)
	if port == unsafe { nil } { return 15 }
	unsafe { *output = if port.dead { u32(0x100000) } else { u32(0x10000) } }
	return 0
}

fn darwin_mach_port_get_refs(task u32, name u32, right i32, output &u32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if task != system_data.task_self || output == unsafe { nil } { return 4 }
	$if macos { return C.ios_native_port_refs(name, right, output) }
	if right < 0 || right > 5 { return 18 }
	if name == 0 || name == 0xffffffff {
		if right == 0 || right == 2 { unsafe { *output = 1 }; return 0 }
		return 15
	}
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	mach_threads_refresh()
	port := mach_thread_find(name)
	if port == unsafe { nil } { return 15 }
	unsafe { *output = if right == (if port.dead { i32(4) } else { i32(0) }) { port.refs } else { u32(0) } }
	return 0
}

fn darwin_mach_port_mod_refs(task u32, name u32, right i32, delta i32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if task != system_data.task_self { return 4 }
	$if macos { return C.ios_native_port_mod_refs(name, right, delta) }
	if right < 0 || right > 4 { return 18 }
	if delta < -65535 || delta > 65535 { return 18 }
	if name == 0 || name == 0xffffffff { return if right == 0 || right == 2 { i32(0) } else { i32(15) } }
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	mach_threads_refresh()
	mut port := mach_thread_find(name)
	if port == unsafe { nil } { return 15 }
	if right != (if port.dead { i32(4) } else { i32(0) }) { return 17 }
	// Overflow pins reference counts. Saturated dead names can still be
	// removed in full; removing all saturated live send rights is invalid.
	if port.refs == 65535 {
		if delta != -65535 { return 0 }
		if !port.dead { return 20 }
		port.refs = 0
		mach_threads_refresh()
		return 0
	}
	refs := i64(port.refs) + i64(delta)
	if refs < 0 { return 18 }
	port.refs = u32(if refs > 65535 { i64(65535) } else { refs })
	if port.refs == 0 { port.borrowed = false }
	mach_threads_refresh()
	return 0
}

fn darwin_mach_port_deallocate(task u32, name u32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if task != system_data.task_self { return 4 }
	$if macos { return C.ios_native_port_deallocate(name) }
	if name == 0 || name == 0xffffffff { return 0 }
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	mach_threads_refresh()
	mut port := mach_thread_find(name)
	if port == unsafe { nil } { return 15 }
	if port.refs != 65535 { port.refs-- }
	if port.refs == 0 { port.borrowed = false }
	mach_threads_refresh()
	return 0
}

fn mach_threads_symbol(symbol string) ?u64 {
	return match symbol {
		'_pthread_mach_thread_np' { u64(unsafe { voidptr(darwin_pthread_mach_thread_np) }) }
		'_pthread_from_mach_thread_np' { u64(unsafe { voidptr(darwin_pthread_from_mach_thread_np) }) }
		'_mach_thread_self' { u64(unsafe { voidptr(darwin_mach_thread_self) }) }
		'_mach_port_type' { u64(unsafe { voidptr(darwin_mach_port_type) }) }
		'_mach_port_get_refs' { u64(unsafe { voidptr(darwin_mach_port_get_refs) }) }
		'_mach_port_mod_refs' { u64(unsafe { voidptr(darwin_mach_port_mod_refs) }) }
		'_mach_port_deallocate' { u64(unsafe { voidptr(darwin_mach_port_deallocate) }) }
		else { return none }
	}
}
