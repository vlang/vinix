// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.__builtin_alloca(usize) voidptr

struct MachSemWaiter {
mut:
	next   &MachSemWaiter = unsafe { nil }
	result i32            = -1
}

struct MachSemaphore {
mut:
	next       &MachSemaphore = unsafe { nil }
	name       u32
	refs       u32
	calls      u64
	count      u32
	lifo       bool
	terminated bool
	guard      voidptr
	changed    voidptr
	head       &MachSemWaiter = unsafe { nil }
	tail       &MachSemWaiter = unsafe { nil }
}

// Distinct from thread names (low byte 3), and never reused across images.
// The high range also separates host reference tests from native Mac ports.
__global mach_semaphore_next_name = u64(0x70000107)

fn mach_semaphore_known(name u32) bool {
	return name >= 0x70000107 && u64(name) < mach_semaphore_next_name && name & 0xff == 7
}

// The shared namespace lock protects names, send references and call pins.
fn mach_semaphore_find(name u32) &MachSemaphore {
	if system_data == unsafe { nil } { return unsafe { nil } }
	mut state := system_data.semaphores
	for state != unsafe { nil } {
		if state.name == name && state.refs != 0 { return state }
		state = state.next
	}
	return unsafe { nil }
}

fn mach_semaphore_free(state &MachSemaphore) {
	if C.pthread_cond_destroy(state.changed) != 0 || C.pthread_mutex_destroy(state.guard) != 0 {
		panic('iOS: active native semaphore at retirement')
	}
	C.free(state.changed)
	C.free(state.guard)
	C.free(state)
}

fn mach_semaphores_refresh() {
	mut previous := unsafe { &MachSemaphore(nil) }
	mut state := system_data.semaphores
	for state != unsafe { nil } {
		next := state.next
		if state.refs == 0 && state.calls == 0 {
			if previous == unsafe { nil } {
				system_data.semaphores = next
			} else {
				previous.next = next
			}
			mach_semaphore_free(state)
		} else {
			previous = state
		}
		state = next
	}
}

fn mach_semaphore_pin(name u32) ?&MachSemaphore {
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	mut state := mach_semaphore_find(name)
	if state == unsafe { nil } { return none }
	state.calls++
	return state
}

fn mach_semaphore_unpin(mut state MachSemaphore) {
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	if state.calls == 0 { panic('iOS: semaphore call reference underflow') }
	state.calls--
	mach_semaphores_refresh()
}

fn mach_semaphore_bad_name(name u32, destroying bool) i32 {
	if name == 0 || name == 0xffffffff { return if destroying { i32(4) } else { i32(15) } }
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	if !mach_semaphore_known(name) && system_data != unsafe { nil } {
		if mach_memory_find(name) != unsafe { nil } { return if destroying { i32(4) } else { i32(20) } }
		$if macos {
			mut kind := u32(0)
			if C.ios_native_port_type(name, unsafe { &kind }) == 0 {
				return if destroying { i32(4) } else { i32(20) }
			}
		} $else {
			mach_threads_refresh()
			if mach_host_live(name) { return if destroying { i32(4) } else { i32(20) } }
			if mach_thread_find(name) != unsafe { nil } {
				return if destroying { i32(4) } else { i32(20) }
			}
		}
	}
	// Destroy is a MIG call with a send-right argument; signal/wait are traps.
	return if destroying { i32(0x1000000a) } else { i32(15) }
}

fn darwin_semaphore_create(task u32, output &u32, policy i32, initial i32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if system_data == unsafe { nil } || task != system_data.task_self || output == unsafe { nil } || initial < 0 || policy !in [
		i32(0),
		2,
	] {
		return 4
	}
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	if mach_semaphore_next_name >= 0xffffffff { return 6 }
	mut state := unsafe { &MachSemaphore(C.calloc(1, sizeof(MachSemaphore))) }
	if state == unsafe { nil } { return 6 }
	unsafe { *state = MachSemaphore{ name: u32(mach_semaphore_next_name), refs: 1, count: u32(initial), lifo: policy == 2 } }
	state.guard = C.calloc(1, C.ios_sizeof_mutex())
	state.changed = C.calloc(1, C.ios_sizeof_cond())
	if state.guard == unsafe { nil } || state.changed == unsafe { nil } {
		C.free(state.guard)
		C.free(state.changed)
		C.free(state)
		return 6
	}
	if C.ios_mutex_create(state.guard, 0) != 0 {
		C.free(state.guard)
		C.free(state.changed)
		C.free(state)
		return 6
	}
	if C.pthread_cond_init(state.changed, unsafe { nil }) != 0 {
		C.pthread_mutex_destroy(state.guard)
		C.free(state.guard)
		C.free(state.changed)
		C.free(state)
		return 6
	}
	state.next = system_data.semaphores
	system_data.semaphores = state
	mach_semaphore_next_name += 0x100
	unsafe { *output = state.name }
	return 0
}

// Caller holds the object's native guard. Wait nodes belong to pinned calls,
// and remain on their threads' stacks until the native wait returns.
fn mach_semaphore_terminate(mut state MachSemaphore) {
	state.terminated = true
	state.count = 0
	mut waiter := state.head
	state.head = unsafe { nil }
	state.tail = unsafe { nil }
	for waiter != unsafe { nil } {
		next := waiter.next
		waiter.next = unsafe { nil }
		waiter.result = 37
		waiter = next
	}
	if C.pthread_cond_broadcast(state.changed) != 0 { panic('iOS: cannot wake semaphore waiters') }
}

fn darwin_semaphore_destroy(task u32, name u32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if system_data == unsafe { nil } || task != system_data.task_self { return 4 }
	mut state := mach_semaphore_pin(name) or { return mach_semaphore_bad_name(name, true) }
	defer { mach_semaphore_unpin(mut state) }
	C.ios_mach_threads_lock()
	if state.refs != 0 && state.refs != 65535 { state.refs-- }
	C.ios_mach_threads_unlock()
	if C.pthread_mutex_lock(state.guard) != 0 { panic('iOS: cannot guard semaphore') }
	defer { C.pthread_mutex_unlock(state.guard) }
	mach_semaphore_terminate(mut state)
	return 0
}

fn darwin_semaphore_signal(name u32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	mut state := mach_semaphore_pin(name) or { return mach_semaphore_bad_name(name, false) }
	defer { mach_semaphore_unpin(mut state) }
	if C.pthread_mutex_lock(state.guard) != 0 { panic('iOS: cannot guard semaphore') }
	defer { C.pthread_mutex_unlock(state.guard) }
	if state.terminated { return 37 }
	if state.head != unsafe { nil } {
		mut waiter := state.head
		state.head = waiter.next
		if state.head == unsafe { nil } { state.tail = unsafe { nil } }
		waiter.next = unsafe { nil }
		waiter.result = 0
		if C.pthread_cond_broadcast(state.changed) != 0 { panic('iOS: cannot signal semaphore') }
	} else {
		// Avoid the measured native signed-count wraparound. This bound is
		// explicit rather than accepting a credit that could never be waited.
		if state.count == 0x7fffffff { return 6 }
		state.count++
	}
	return 0
}

fn darwin_semaphore_wait(name u32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	mut state := mach_semaphore_pin(name) or { return mach_semaphore_bad_name(name, false) }
	defer { mach_semaphore_unpin(mut state) }
	if C.pthread_mutex_lock(state.guard) != 0 { panic('iOS: cannot guard semaphore') }
	defer { C.pthread_mutex_unlock(state.guard) }
	if state.terminated { return 37 }
	if state.count != 0 {
		state.count--
		return 0
	}
	// Taking a V local's address can move it to the heap even in unsafe.
	// Native stack storage lasts through this call and needs no retirement.
	mut waiter := unsafe { &MachSemWaiter(C.__builtin_alloca(sizeof(MachSemWaiter))) }
	unsafe { *waiter = MachSemWaiter{} }
	if state.head == unsafe { nil } {
		state.head = waiter
		state.tail = waiter
	} else if state.lifo {
		waiter.next = state.head
		state.head = waiter
	} else {
		state.tail.next = waiter
		state.tail = waiter
	}
	for waiter.result == -1 {
		if C.pthread_cond_wait(state.changed, state.guard) != 0 {
			// Remove this stack node before its call pin can be released.
			mut previous_waiter := unsafe { &MachSemWaiter(nil) }
			mut cursor := state.head
			for cursor != unsafe { nil } {
				if voidptr(cursor) == voidptr(waiter) {
					if previous_waiter == unsafe { nil } {
						state.head = cursor.next
					} else {
						previous_waiter.next = cursor.next
					}
					if voidptr(state.tail) == voidptr(cursor) { state.tail = previous_waiter }
					break
				}
				previous_waiter = cursor
				cursor = cursor.next
			}
			return 14
		}
	}
	return waiter.result
}

// Optional results distinguish our port names from native thread ports. Each
// helper holds the namespace lock; operations never acquire it while holding
// the object's guard, so last-right removal can safely wake pinned waiters.
fn mach_semaphore_port_type(name u32, output &u32) ?i32 {
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	state := mach_semaphore_find(name)
	if state == unsafe { nil } {
		if mach_semaphore_known(name) { return i32(15) }
		return none
	}
	unsafe { *output = 0x10000 }
	return i32(0)
}

fn mach_semaphore_port_refs(name u32, right i32, output &u32) ?i32 {
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	if !mach_semaphore_known(name) { return none }
	if right < 0 || right > 5 { return i32(18) }
	state := mach_semaphore_find(name)
	if state == unsafe { nil } { return i32(15) }
	unsafe { *output = if right == 0 { state.refs } else { u32(0) } }
	return i32(0)
}

fn mach_semaphore_port_mod_refs(name u32, right i32, delta i32) ?i32 {
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	if !mach_semaphore_known(name) { return none }
	if right < 0 || right > 5 || delta < -65535 || delta > 65535 { return i32(18) }
	mut state := mach_semaphore_find(name)
	if state == unsafe { nil } { return i32(15) }
	if right != 0 { return i32(17) }
	if state.refs == 65535 { return if delta == -65535 { i32(20) } else { i32(0) } }
	refs := i64(state.refs) + i64(delta)
	if refs < 0 { return i32(18) }
	state.refs = u32(if refs > 65535 { i64(65535) } else { refs })
	if state.refs == 0 {
		if C.pthread_mutex_lock(state.guard) != 0 { panic('iOS: cannot retire semaphore') }
		mach_semaphore_terminate(mut state)
		C.pthread_mutex_unlock(state.guard)
		mach_semaphores_refresh()
	}
	return i32(0)
}

fn mach_semaphore_port_deallocate(name u32) ?i32 {
	return mach_semaphore_port_mod_refs(name, 0, -1)
}

fn mach_semaphores_clear(forked bool) {
	if system_data == unsafe { nil } { return }
	mut state := system_data.semaphores
	system_data.semaphores = unsafe { nil }
	for state != unsafe { nil } {
		next := state.next
		if forked {
			// Inherited Mach semaphore rights are outside this backend's
			// process-private subset. Vanished threads may own native bytes;
			// discard the child copies without touching their wait queues.
			C.free(state.changed)
			C.free(state.guard)
			C.free(state)
		} else {
			if state.calls != 0 { panic('iOS: active semaphore at image shutdown') }
			mach_semaphore_free(state)
		}
		state = next
	}
}

fn mach_semaphores_stop() {
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	mach_semaphores_clear(false)
}

fn mach_semaphore_symbol(symbol string) ?u64 {
	return match symbol {
		'_semaphore_create' { u64(unsafe { voidptr(darwin_semaphore_create) }) }
		'_semaphore_destroy' { u64(unsafe { voidptr(darwin_semaphore_destroy) }) }
		'_semaphore_signal' { u64(unsafe { voidptr(darwin_semaphore_signal) }) }
		'_semaphore_wait' { u64(unsafe { voidptr(darwin_semaphore_wait) }) }
		else { return none }
	}
}
