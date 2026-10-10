// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.ios_sizeof_rwlock() usize
fn C.pthread_rwlock_init(voidptr, voidptr) i32
fn C.pthread_rwlock_destroy(voidptr) i32
fn C.pthread_rwlock_tryrdlock(voidptr) i32
fn C.pthread_rwlock_trywrlock(voidptr) i32
fn C.pthread_rwlock_unlock(voidptr) i32

// Native objects provide actual exclusion and blocking. V keeps Darwin's
// writer preference, writer identity and call references outside opaque bytes.
struct DarwinRwlock {
mut:
	native voidptr
	guard voidptr
	changed voidptr
	readers u64
	writer u64
	writer_waited bool
	waiting_writers u64
	calls u64
}

fn pthread_rwlockattr_valid(attributes u64) bool {
	return attributes != 0 && read64(attributes) == 0x52574c41
}

fn darwin_rwlockattr_init(attributes u64) i32 {
	if attributes == 0 { return 22 }
	unsafe { *(&u64(attributes)) = 0x52574c41 }
	write32(attributes + 8, 2)
	return 0
}

fn darwin_rwlockattr_destroy(attributes u64) i32 {
	if attributes == 0 { return 22 }
	// The native operation also clears invalid and already-destroyed values.
	unsafe { *(&u64(attributes)) = 0 }
	write32(attributes + 8, 0)
	return 0
}

fn darwin_rwlockattr_getshared(attributes u64, output &i32) i32 {
	if !pthread_rwlockattr_valid(attributes) || output == unsafe { nil } { return 22 }
	unsafe { *output = i32(read32(attributes + 8)) }
	return 0
}

fn darwin_rwlockattr_setshared(attributes u64, state i32) i32 {
	if !pthread_rwlockattr_valid(attributes) || (state != 1 && state != 2) { return 22 }
	write32(attributes + 8, u32(state))
	return 0
}

fn pthread_rwlock_pin(object u64, initialize bool) !&DarwinRwlock {
	if object == 0 { return error_with_code('null rwlock', 22) }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if mut state := system_data.rwlocks[object] {
		if initialize { return error_with_code('rwlock already initialized', 22) }
		state.calls++
		return state
	}
	if !initialize && read64(object) != 0x2da8b3b4 { return error_with_code('invalid rwlock signature', 22) }
	mut state := unsafe { &DarwinRwlock(C.calloc(1, sizeof(DarwinRwlock))) }
	if state == unsafe { nil } { return error_with_code('cannot allocate rwlock state', 12) }
	state.native = C.calloc(1, C.ios_sizeof_rwlock())
	state.guard = C.calloc(1, C.ios_sizeof_mutex())
	state.changed = C.calloc(1, C.ios_sizeof_cond())
	if state.native == unsafe { nil } || state.guard == unsafe { nil } || state.changed == unsafe { nil } {
		C.free(state.native); C.free(state.guard); C.free(state.changed); C.free(state)
		return error_with_code('cannot allocate native rwlock', 12)
	}
	mut result := C.ios_mutex_create(state.guard, 0)
	if result == 0 {
		result = int(C.pthread_cond_init(state.changed, unsafe { nil }))
		if result == 0 {
			result = int(C.pthread_rwlock_init(state.native, unsafe { nil }))
			if result != 0 { C.pthread_cond_destroy(state.changed) }
		}
		if result != 0 { C.pthread_mutex_destroy(state.guard) }
	}
	if result != 0 {
		C.free(state.native); C.free(state.guard); C.free(state.changed); C.free(state)
		return error_with_code('native rwlock initialization failed', pthread_error(result))
	}
	state.calls = 1
	system_data.rwlocks[object] = state
	unsafe { *(&u64(object)) = 0x52574c4b }
	return state
}

fn pthread_rwlock_unpin(mut state DarwinRwlock) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if state.calls == 0 { panic('iOS: rwlock reference underflow') }
	state.calls--
}

fn darwin_rwlock_init(object u64, attributes u64) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if object == 0 { return 22 }
	if attributes != 0 {
		if !pthread_rwlockattr_valid(attributes) { return 22 }
		if read32(attributes + 8) != 2 { return 45 }
	}
	mut state := pthread_rwlock_pin(object, true) or { return i32(err.code()) }
	pthread_rwlock_unpin(mut state)
	return 0
}

fn pthread_rwlock_enter(object u64, writing bool, attempt bool) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	mut state := pthread_rwlock_pin(object, false) or { return i32(err.code()) }
	defer { pthread_rwlock_unpin(mut state) }
	if C.pthread_mutex_lock(state.guard) != 0 { panic('iOS: cannot guard rwlock') }
	defer { C.pthread_mutex_unlock(state.guard) }
	identity := u64(C.pthread_self())
	if state.writer == identity {
		// Native Mac try-locks report BUSY after a contended writer handoff.
		if attempt && state.writer_waited { return 16 }
		return 11
	}
	if writing {
		if attempt && (state.writer != 0 || state.readers != 0) { return 16 }
		state.waiting_writers++
		mut waited := false
		for state.writer != 0 || state.readers != 0 {
			waited = true
			result := C.pthread_cond_wait(state.changed, state.guard)
			if result != 0 {
				state.waiting_writers--
				C.pthread_cond_broadcast(state.changed)
				return i32(pthread_error(int(result)))
			}
		}
		state.waiting_writers--
		result := C.pthread_rwlock_trywrlock(state.native)
		if result == 0 { state.writer = identity; state.writer_waited = waited } else { C.pthread_cond_broadcast(state.changed) }
		return i32(pthread_error(int(result)))
	}
	if attempt && (state.writer != 0 || state.waiting_writers != 0) { return 16 }
	for state.writer != 0 || state.waiting_writers != 0 {
		result := C.pthread_cond_wait(state.changed, state.guard)
		if result != 0 { return i32(pthread_error(int(result))) }
	}
	result := C.pthread_rwlock_tryrdlock(state.native)
	if result == 0 { state.readers++ }
	return i32(pthread_error(int(result)))
}

fn darwin_rwlock_read(object u64) i32 { return pthread_rwlock_enter(object, false, false) }
fn darwin_rwlock_tryread(object u64) i32 { return pthread_rwlock_enter(object, false, true) }
fn darwin_rwlock_write(object u64) i32 { return pthread_rwlock_enter(object, true, false) }
fn darwin_rwlock_trywrite(object u64) i32 { return pthread_rwlock_enter(object, true, true) }

fn darwin_rwlock_unlock(object u64) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	mut state := pthread_rwlock_pin(object, false) or { return i32(err.code()) }
	defer { pthread_rwlock_unpin(mut state) }
	if C.pthread_mutex_lock(state.guard) != 0 { panic('iOS: cannot guard rwlock release') }
	defer { C.pthread_mutex_unlock(state.guard) }
	// Measured Darwin accepts an unheld unlock. Avoid underflow in musl.
	if state.writer == 0 && state.readers == 0 { return 0 }
	result := C.pthread_rwlock_unlock(state.native)
	if result == 0 {
		if state.writer != 0 { state.writer = 0 } else { state.readers-- }
		if state.writer == 0 && state.readers == 0 { C.pthread_cond_broadcast(state.changed) }
	}
	return i32(pthread_error(int(result)))
}

fn pthread_rwlock_free(state &DarwinRwlock) {
	if C.pthread_rwlock_destroy(state.native) != 0 || C.pthread_cond_destroy(state.changed) != 0
		|| C.pthread_mutex_destroy(state.guard) != 0 { panic('iOS: active native rwlock at destruction') }
	C.free(state.native); C.free(state.changed); C.free(state.guard); C.free(state)
}

fn darwin_rwlock_destroy(object u64) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	mut state := pthread_rwlock_pin(object, false) or { return i32(err.code()) }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	// Each lock/unlock caller pins under this same registry lock before it can
	// touch native state. Sole reference means fields and native objects are
	// quiescent; held ownership or any other (including waiting) caller is busy.
	if state.calls != 1 || state.writer != 0 || state.readers != 0 {
		state.calls--
		return 16
	}
	system_data.rwlocks.delete(object)
	pthread_rwlock_free(state)
	unsafe { *(&u64(object)) = 0 }
	return 0
}

fn pthread_rwlocks_stop() {
	for _, state in system_data.rwlocks {
		if state.calls != 0 || state.writer != 0 || state.readers != 0 || state.waiting_writers != 0 {
			panic('iOS: active rwlock at image shutdown')
		}
		pthread_rwlock_free(state)
	}
}

fn pthread_rwlock_symbol(symbol string) ?u64 {
	return match symbol {
		'_pthread_rwlockattr_init' { u64(unsafe { voidptr(darwin_rwlockattr_init) }) }
		'_pthread_rwlockattr_destroy' { u64(unsafe { voidptr(darwin_rwlockattr_destroy) }) }
		'_pthread_rwlockattr_getpshared' { u64(unsafe { voidptr(darwin_rwlockattr_getshared) }) }
		'_pthread_rwlockattr_setpshared' { u64(unsafe { voidptr(darwin_rwlockattr_setshared) }) }
		'_pthread_rwlock_init' { u64(unsafe { voidptr(darwin_rwlock_init) }) }
		'_pthread_rwlock_destroy' { u64(unsafe { voidptr(darwin_rwlock_destroy) }) }
		'_pthread_rwlock_rdlock' { u64(unsafe { voidptr(darwin_rwlock_read) }) }
		'_pthread_rwlock_tryrdlock' { u64(unsafe { voidptr(darwin_rwlock_tryread) }) }
		'_pthread_rwlock_wrlock' { u64(unsafe { voidptr(darwin_rwlock_write) }) }
		'_pthread_rwlock_trywrlock' { u64(unsafe { voidptr(darwin_rwlock_trywrite) }) }
		'_pthread_rwlock_unlock' { u64(unsafe { voidptr(darwin_rwlock_unlock) }) }
		else { return none }
	}
}
