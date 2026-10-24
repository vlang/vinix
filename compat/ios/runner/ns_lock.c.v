// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

// Measured ARM64 Foundation layout. The mutex is a short-lived state gate;
// ownership is tracked separately to reject invalid unlocks.
struct AbiNSLock {
mut:
	isa u64
	mutex [8]u64
	condition u64
	name u64
}

struct FoundationLockState {
mut:
	mutex voidptr
	condition voidptr
	owner u64
}

fn ns_lock_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSLock' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic lock superclass chain')
}

fn ns_lock_require_class(cls u64) {
	if ns_lock_family(cls) && cls != ios_runtime.names['NSLock'] {
		panic('iOS: custom NSLock subclass construction is not implemented')
	}
}

fn ns_lock_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['NSLock']] or { panic('iOS: missing lock class') }
	cls.ivars['_priv'] = &ObjIvar{name: '_priv'.clone(), types: '{?="m"{_opaque_pthread_mutex_t="__sig"q"__opaque"[56c]}"cd"^{?}"n"@"NSString"}'.clone(), offset: 8, size: 80}
}

// All allocation/provenance checks and call pins use the runtime lock. No
// blocking gate, condition wait or application callback runs under that lock.
fn ns_lock_state(object u64) &ObjHeader {
	header := obj_header(object)
	if !header.foundation_lock_owned || header.native_size < sizeof(AbiNSLock)
		|| header.allocation_cls != ios_runtime.names['NSLock']
		|| header.cls != header.allocation_cls || read64(object) != header.cls
		|| header.foundation_lock_retiring || header.destroying || header.destroyed {
		panic('iOS: NSLock requires live base lock storage')
	}
	return header
}

fn ns_lock_begin(object u64, initialized bool) &ObjHeader {
	objc_retain(object)
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut header := ns_lock_state(object)
	if initialized && header.foundation_lock == unsafe { nil } { panic('iOS: NSLock is not initialized') }
	if header.foundation_lock_calls == ~u64(0) { panic('iOS: NSLock call count overflow') }
	header.foundation_lock_calls++
	return header
}

fn ns_lock_end(object u64, mut header ObjHeader) {
	C.ios_objc_initialize_lock()
	header.foundation_lock_calls--
	C.ios_objc_initialize_unlock()
	objc_release(object)
}

fn ns_lock_initialize(object u64) {
	mut header := ns_lock_begin(object, false)
	defer { ns_lock_end(object, mut header) }
	retired := ns_lock_initialize_locked(object)
	objc_release(retired)
}

fn ns_lock_initialize_locked(object u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut header := ns_lock_state(object)
	if header.foundation_lock != unsafe { nil } { panic('iOS: NSLock reinitialization is not implemented') }
	if system_data == unsafe { nil } { panic('iOS: NSLock requires initialized system data') }
	mut state := unsafe { &FoundationLockState(C.calloc(1, sizeof(FoundationLockState))) }
	if state == unsafe { nil } { panic('iOS: cannot allocate lock state') }
	state.mutex = pthread_mutex_native(object + 8, 0) or { C.free(state); panic('iOS: lock gate initialization failed') }
	state.condition = C.calloc(1, C.ios_sizeof_cond())
	if state.condition == unsafe { nil } {
		darwin_mutex_destroy(object + 8)
		C.free(state)
		panic('iOS: cannot allocate lock condition')
	}
	if C.pthread_cond_init(state.condition, unsafe { nil }) != 0 {
		C.free(state.condition)
		darwin_mutex_destroy(object + 8)
		C.free(state)
		panic('iOS: lock condition initialization failed')
	}
	header.foundation_lock = state
	unsafe { *(&u64(object + 8)) = 0x4d555458 }
	// First init clears even a name set on raw allocated storage. Retire that
	// copied value after unlocking, with the initializer's receiver pin intact.
	retired := header.fields[0]
	header.fields[0] = 0
	unsafe { *(&u64(object + 80)) = 0 }
	return retired
}

fn ns_lock_retire(mut header ObjHeader) {
	if !header.foundation_lock_owned { return }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if header.foundation_lock_calls != 0 || (header.foundation_lock != unsafe { nil } && header.foundation_lock.owner != 0) {
		panic('iOS: destroying an active NSLock')
	}
	header.foundation_lock_retiring = true
}

fn ns_lock_dispose(object u64, mut header ObjHeader) {
	if !header.foundation_lock_owned { return }
	state := header.foundation_lock
	if state != unsafe { nil } {
		if system_data == unsafe { nil } { panic('iOS: NSLock outlived system data') }
		if C.pthread_cond_destroy(state.condition) != 0 || darwin_mutex_destroy(object + 8) != 0 {
			panic('iOS: lock synchronization disposal failed')
		}
		C.free(state.condition)
		C.free(state)
		header.foundation_lock = unsafe { nil }
	}
	// The generic owned-field disposer releases the copied name after all
	// synchronization storage has retired, independently of object_setClass.
	unsafe { C.memset(voidptr(object + 8), 0, 80) }
	header.foundation_lock_owned = false
}

fn ns_lock_deadline(date u64) DispatchTimespec {
	absolute := if date == 0 { f64(-978307200) } else { cf_date_absolute(date) }
	seconds := absolute + 978307200
	if !math.is_finite(seconds) || seconds >= 9223372036854775808.0 {
		panic('iOS: NSLock deadline is outside the finite clock profile')
	}
	clamped := math.max(seconds, 0)
	whole := math.floor(clamped)
	return DispatchTimespec{seconds: i64(whole), nanoseconds: i64((clamped - whole) * 1e9)}
}

fn ns_lock_operate(object u64, selector string, date u64, mut state FoundationLockState) bool {
	mut deadline := DispatchTimespec{}
	if selector == 'lockBeforeDate:' { deadline = ns_lock_deadline(date) }
	if C.pthread_mutex_lock(state.mutex) != 0 { panic('iOS: lock gate failed') }
	defer {
		if C.pthread_mutex_unlock(state.mutex) != 0 { panic('iOS: lock gate unlock failed') }
	}
	owner_thread := u64(C.pthread_self())
	if selector == 'unlock' {
		if state.owner != owner_thread { panic('iOS: NSLock unlock requires the owning thread') }
		state.owner = 0
	} else {
		for state.owner != 0 {
			if selector == 'tryLock' { return false }
			result := if selector == 'lockBeforeDate:' {
				C.pthread_cond_timedwait(state.condition, state.mutex, unsafe { voidptr(&deadline) })
			} else { C.pthread_cond_wait(state.condition, state.mutex) }
			if result == C.ETIMEDOUT { return false }
			if result != 0 { panic('iOS: lock wait failed') }
		}
		state.owner = owner_thread
	}
	// Wake every contender so an expired timed waiter cannot consume the only
	// wakeup while an untimed caller remains asleep on a now available lock.
	if selector == 'unlock' && C.pthread_cond_broadcast(state.condition) != 0 {
		panic('iOS: lock signal failed')
	}
	return true
}

fn ns_lock_types(name string, meta bool, selector string) ?string {
	if name != 'NSLock' || meta { return none }
	return match selector {
		'init', 'name' { '@16@0:8' }
		'lock', 'unlock' { 'v16@0:8' }
		'tryLock' { 'B16@0:8' }
		'lockBeforeDate:' { 'B24@0:8@16' }
		'setName:' { 'v24@0:8@16' }
		else { return none }
	}
}

fn ns_lock_unsupported(selector string) bool {
	return selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:',
		'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'description']!
		|| selector.starts_with('initWith')
}

fn ns_lock_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	if !ns_lock_family(if meta { object } else { read64(object) }) { return false }
	if ns_lock_unsupported(selector) { panic('iOS: NSLock copying, coding and this selector are not implemented') }
	if ns_lock_types('NSLock', meta, selector) == none { return false }
	mut header := ns_lock_begin(object, selector !in ['init', 'name', 'setName:']!)
	defer { ns_lock_end(object, mut header) }
	if selector == 'init' { ns_lock_initialize(object); frame.x[0] = object; return true }
	if selector == 'setName:' {
		value := frame.x[2]
		if value != 0 && !objc_is_kind(value, ios_runtime.names['NSString']) { panic('iOS: NSLock name must be NSString') }
		// Copy and release can call application code, including dropping its last
		// reference to this lock. The call pin survives both callbacks.
		copied := if value == 0 { u64(0) } else { objc_copy_value(value, false) }
		if value != 0 && (copied == 0 || !objc_is_kind(copied, ios_runtime.names['NSString'])) {
			panic('iOS: NSLock name copy must return NSString')
		}
		C.ios_objc_initialize_lock()
		retired := header.fields[0]
		header.fields[0] = copied
		unsafe { *(&u64(object + 80)) = copied }
		C.ios_objc_initialize_unlock()
		objc_release(retired)
		return true
	}
	if selector == 'name' {
		C.ios_objc_initialize_lock()
		value := objc_retain(header.fields[0])
		C.ios_objc_initialize_unlock()
		frame.x[0] = objc_autorelease(value)
		return true
	}
	frame.x[0] = u64(ns_lock_operate(object, selector, frame.x[2], mut header.foundation_lock))
	return true
}
