// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.ios_sizeof_mutex() usize
fn C.ios_sizeof_cond() usize
fn C.ios_sizeof_once() usize
fn C.ios_mutex_create(voidptr, int) int
fn C.ios_thread_name(&char) int
fn C.ios_key_create(voidptr, voidptr) int
fn C.pthread_mutex_destroy(voidptr) int
fn C.pthread_mutex_lock(voidptr) int
fn C.pthread_mutex_trylock(voidptr) int
fn C.pthread_mutex_unlock(voidptr) int
fn C.pthread_cond_init(voidptr, voidptr) i32
fn C.pthread_cond_destroy(voidptr) i32
fn C.pthread_cond_signal(voidptr) i32
fn C.pthread_cond_broadcast(voidptr) i32
fn C.pthread_cond_wait(voidptr, voidptr) i32
fn C.pthread_cond_timedwait(voidptr, voidptr, voidptr) i32
fn C.pthread_once(voidptr, voidptr) int
fn C.pthread_self() usize

fn pthread_error(result int) int {
	if result == C.EAGAIN { return 35 }
	if result == C.ETIMEDOUT { return 60 }
	if result == C.EDEADLK { return 11 }
	return result
}

// Darwin's opaque mutexes (64 bytes with a signature) cannot be passed to
// musl (40 bytes). Keep real native synchronization objects in a registry.
fn pthread_mutex_native(object u64, create_type int) !voidptr {
	if object == 0 { return error('null mutex') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if pointer := system_data.mutexes[object] {
		if create_type >= 0 { return error('mutex already initialized') }
		return pointer
	}
	mut kind := create_type
	if kind < 0 {
		kind = match read64(object) {
			0x32aaaba7, 0x32aaaba3 { 0 }
			0x32aaaba1 { 1 }
			0x32aaaba2 { 2 }
			else { return error('invalid Darwin mutex signature') }
		}
	}
	pointer := C.calloc(1, C.ios_sizeof_mutex())
	if pointer == unsafe { nil } { return error('out of memory') }
	if C.ios_mutex_create(pointer, kind) != 0 { C.free(pointer); return error('mutex initialization failed') }
	system_data.mutexes[object] = pointer
	return pointer
}

fn darwin_mutex_init(object u64, attributes u64) int {
	if object == 0 { return 22 }
	kind := if attributes == 0 { 0 } else {
		if read64(attributes) != 0x4d545841 { return 22 }
		int(read32(attributes + 8))
	}
	if kind !in [0, 1, 2] { return 22 }
	pthread_mutex_native(object, kind) or { return 22 }
	unsafe { *(&u64(object)) = 0x32aaaba7 }
	return 0
}

fn darwin_mutex_lock(object u64) int {
	pointer := pthread_mutex_native(object, -1) or { return 22 }
	return pthread_error(C.pthread_mutex_lock(pointer))
}

fn darwin_mutex_trylock(object u64) int {
	pointer := pthread_mutex_native(object, -1) or { return 22 }
	return pthread_error(C.pthread_mutex_trylock(pointer))
}

fn darwin_mutex_unlock(object u64) int {
	pointer := pthread_mutex_native(object, -1) or { return 22 }
	return pthread_error(C.pthread_mutex_unlock(pointer))
}

fn darwin_mutex_destroy(object u64) int {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	pointer := pthread_mutex_native(object, -1) or { return 22 }
	result := C.pthread_mutex_destroy(pointer)
	if result == 0 { system_data.mutexes.delete(object); C.free(pointer); unsafe { *(&u64(object)) = 0 } }
	return pthread_error(result)
}

fn darwin_mutexattr_init(attributes u64) int {
	if attributes == 0 { return 22 }
	unsafe { *(&u64(attributes)) = 0x4d545841 }
	write32(attributes + 8, 0)
	return 0
}

fn darwin_mutexattr_type(attributes u64, kind int) int {
	if attributes == 0 || read64(attributes) != 0x4d545841 || kind !in [0, 1, 2] { return 22 }
	write32(attributes + 8, u32(kind))
	return 0
}

fn darwin_mutexattr_destroy(attributes u64) int {
	if attributes == 0 || read64(attributes) != 0x4d545841 { return 22 }
	unsafe { *(&u64(attributes)) = 0 }
	return 0
}

fn pthread_cond_native(object u64, initialize bool) !voidptr {
	if object == 0 { return error('null condition variable') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if pointer := system_data.conditions[object] {
		if initialize { return error('condition already initialized') }
		return pointer
	}
	if !initialize && read64(object) != 0x3cb0b1bb { return error('invalid Darwin condition signature') }
	pointer := C.calloc(1, C.ios_sizeof_cond())
	if pointer == unsafe { nil } { return error('out of memory') }
	if C.pthread_cond_init(pointer, unsafe { nil }) != 0 { C.free(pointer); return error('condition initialization failed') }
	system_data.conditions[object] = pointer
	return pointer
}

fn darwin_cond_init(object u64, attributes u64) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if object == 0 { return 22 }
	// Native Darwin initialization reads the sharing bits without checking
	// the attribute signature. The registry cannot hold shared process state.
	if attributes != 0 && read32(attributes + 8) & 3 == 1 { return 45 }
	pthread_cond_native(object, true) or { return 22 }
	unsafe { *(&u64(object)) = 0x3cb0b1bb }
	return 0
}

fn darwin_cond_wait(object u64, mutex u64) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	cond := pthread_cond_native(object, false) or { return 22 }
	native_mutex := pthread_mutex_native(mutex, -1) or { return 22 }
	return i32(pthread_error(int(C.pthread_cond_wait(cond, native_mutex))))
}

fn darwin_cond_timedwait(object u64, mutex u64, deadline voidptr) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if deadline == unsafe { nil } { return 22 }
	cond := pthread_cond_native(object, false) or { return 22 }
	native_mutex := pthread_mutex_native(mutex, -1) or { return 22 }
	return i32(pthread_error(int(C.pthread_cond_timedwait(cond, native_mutex, deadline))))
}

fn darwin_cond_signal(object u64) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	cond := pthread_cond_native(object, false) or { return 22 }
	return i32(pthread_error(int(C.pthread_cond_signal(cond))))
}

fn darwin_cond_broadcast(object u64) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	cond := pthread_cond_native(object, false) or { return 22 }
	return i32(pthread_error(int(C.pthread_cond_broadcast(cond))))
}

fn darwin_cond_destroy(object u64) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	cond := pthread_cond_native(object, false) or { return 22 }
	result := C.pthread_cond_destroy(cond)
	if result == 0 { system_data.conditions.delete(object); C.free(cond); unsafe { *(&u64(object)) = 0 } }
	return i32(pthread_error(int(result)))
}

fn darwin_once(control u64, function voidptr) int {
	if control == 0 || function == unsafe { nil } || read64(control) != 0x30b1bcba { return 22 }
	C.ios_objc_initialize_lock()
	mut pointer := system_data.once[control] or { unsafe { nil } }
	if pointer == unsafe { nil } {
		pointer = C.calloc(1, C.ios_sizeof_once())
		if pointer == unsafe { nil } { C.ios_objc_initialize_unlock(); return 12 }
		system_data.once[control] = pointer
	}
	C.ios_objc_initialize_unlock()
	return pthread_error(C.pthread_once(pointer, function))
}

fn darwin_key_create(key &u64, destructor voidptr) int {
	if key == unsafe { nil } { return 22 }
	return pthread_error(C.ios_key_create(key, destructor))
}

fn darwin_thread_name(name &char) int { return pthread_error(C.ios_thread_name(name)) }

fn pthread_symbol(symbol string) ?u64 {
	if address := pthread_attr_symbol(symbol) { return address }
	if address := pthread_condattr_symbol(symbol) { return address }
	if address := pthread_identity_symbol(symbol) { return address }
	if address := pthread_sched_symbol(symbol) { return address }
	if address := mach_threads_symbol(symbol) { return address }
	return match symbol {
		'_pthread_atfork' { u64(unsafe { voidptr(darwin_pthread_atfork) }) }
		'_pthread_mutex_init' { u64(unsafe { voidptr(darwin_mutex_init) }) }
		'_pthread_mutex_lock' { u64(unsafe { voidptr(darwin_mutex_lock) }) }
		'_pthread_mutex_trylock' { u64(unsafe { voidptr(darwin_mutex_trylock) }) }
		'_pthread_mutex_unlock' { u64(unsafe { voidptr(darwin_mutex_unlock) }) }
		'_pthread_mutex_destroy' { u64(unsafe { voidptr(darwin_mutex_destroy) }) }
		'_pthread_mutexattr_init' { u64(unsafe { voidptr(darwin_mutexattr_init) }) }
		'_pthread_mutexattr_settype' { u64(unsafe { voidptr(darwin_mutexattr_type) }) }
		'_pthread_mutexattr_destroy' { u64(unsafe { voidptr(darwin_mutexattr_destroy) }) }
		'_pthread_cond_init' { u64(unsafe { voidptr(darwin_cond_init) }) }
		'_pthread_cond_wait' { u64(unsafe { voidptr(darwin_cond_wait) }) }
		'_pthread_cond_timedwait' { u64(unsafe { voidptr(darwin_cond_timedwait) }) }
		'_pthread_cond_signal' { u64(unsafe { voidptr(darwin_cond_signal) }) }
		'_pthread_cond_broadcast' { u64(unsafe { voidptr(darwin_cond_broadcast) }) }
		'_pthread_cond_destroy' { u64(unsafe { voidptr(darwin_cond_destroy) }) }
		'_pthread_once' { u64(unsafe { voidptr(darwin_once) }) }
		'_pthread_key_create' { u64(unsafe { voidptr(darwin_key_create) }) }
		'_pthread_key_delete' { u64(unsafe { voidptr(C.pthread_key_delete) }) }
		'_pthread_getspecific' { u64(unsafe { voidptr(C.pthread_getspecific) }) }
		'_pthread_setspecific' { u64(unsafe { voidptr(C.pthread_setspecific) }) }
		'_pthread_self' { u64(unsafe { voidptr(C.pthread_self) }) }
		'_pthread_setname_np' { u64(unsafe { voidptr(darwin_thread_name) }) }
		else { return none }
	}
}
