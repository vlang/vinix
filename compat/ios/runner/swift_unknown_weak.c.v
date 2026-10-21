// SPDX-License-Identifier: GPL-2.0-or-later
module main

// WeakReference is one opaque pointer-sized cell. Keep the referent in a
// runtime registry as well: an arbitrary application word must never authorize
// a header read, and deallocation must clear every copy before freeing bytes.
enum SwiftUnknownWeakOperation {
	initialize
	assign
	copy_initialize
	take_initialize
	copy_assign
	take_assign
}

struct SwiftUnknownWeakFailure {}
fn (_ &SwiftUnknownWeakFailure) msg() string { return 'iOS: invalid or unsupported Swift unknown-object weak reference' }
fn (_ &SwiftUnknownWeakFailure) code() int { return 1 }
__global swift_unknown_weak_failure_value = SwiftUnknownWeakFailure{}
fn swift_unknown_weak_failure() IError { return unsafe { &swift_unknown_weak_failure_value } }

fn swift_unknown_weak_address(location u64) ! {
	if location == 0 || location & 7 != 0 || location > ~u64(0) - 8
		|| ios_runtime == unsafe { nil } { return swift_unknown_weak_failure() }
}

// All helpers ending in _locked require the recursive ObjC runtime lock.
fn swift_unknown_weak_read_locked(location u64) !u64 {
	word := read64(location)
	if value := ios_runtime.swift_unknown_weak[location] {
		if word != value { return swift_unknown_weak_failure() }
		return value
	}
	// Zero-initialized image/global storage is a valid empty weak reference.
	if word != 0 { return swift_unknown_weak_failure() }
	return 0
}

fn swift_unknown_weak_immortal_locked(object u64) bool {
	return object == 0 || object >> 63 != 0 || object in ios_runtime.classes
		|| object in ios_runtime.constants || object == ios_runtime.swift_empty_array
		|| object == ios_runtime.swift_empty_set || swift_dictionary_empty_locked(object)
		|| swift_json_decoder_empty_locked(object) || swift_json_encoder_empty_locked(object)
		|| swift_main_actor_is_singleton_locked(object) || swift_main_executor_is_singleton_locked(object)
		|| swift_static_object_registered_locked(object)
}

fn swift_unknown_weak_native_locked(object u64) bool {
	return object in ios_runtime.swift_heap || object in ios_runtime.swift_buffers
		|| object in ios_runtime.swift_strings || object in ios_runtime.swift_arrays
		|| swift_task_find_locked(object) != 0
}

fn swift_unknown_weak_live_locked(object u64) !u64 {
	if swift_unknown_weak_immortal_locked(object) { return object }
	if swift_unknown_weak_native_locked(object) {
		bits := C.ios_load_pointer(unsafe { &u64(object + 8) })
		if bits == 0x100000003 { return 0 }
		if bits & 0x80000001ffffffff != 3 { return swift_unknown_weak_failure() }
		return object
	}
	if header := ios_runtime.objects[object] {
		// Pools and scheduler objects have different ownership protocols.
		if header.pool_owned { return swift_unknown_weak_failure() }
		if header.destroying || header.destroyed || C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 { return 0 }
		return object
	}
	// In particular, do not read unregistered pointers, Blocks, borrowed stack
	// headers, dispatch handles or os_log handles as ObjHeader/Swift storage.
	return swift_unknown_weak_failure()
}

fn swift_unknown_weak_write_locked(location u64, value u64) {
	ios_runtime.swift_unknown_weak[location] = value
	unsafe { *(&u64(location)) = value }
}

fn swift_unknown_weak_retire_locked(object u64) {
	for location, referent in ios_runtime.swift_unknown_weak {
		if referent == object { swift_unknown_weak_write_locked(location, 0) }
	}
}

fn swift_unknown_weak_update_checked(destination u64, source u64, object u64, operation SwiftUnknownWeakOperation) !u64 {
	swift_unknown_weak_address(destination)!
	copying := operation in [.copy_initialize, .take_initialize, .copy_assign, .take_assign]
	initializing := operation in [.initialize, .copy_initialize, .take_initialize]
	taking := operation in [.take_initialize, .take_assign]
	if copying { swift_unknown_weak_address(source)! }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if initializing {
		// Initialization may receive arbitrary uninitialized bytes. Never read them.
		if destination in ios_runtime.swift_unknown_weak { return swift_unknown_weak_failure() }
	} else { swift_unknown_weak_read_locked(destination)! }
	if copying && destination == source && (initializing || taking) { return swift_unknown_weak_failure() }
	value := swift_unknown_weak_live_locked(if copying { swift_unknown_weak_read_locked(source)! } else { object })!
	swift_unknown_weak_write_locked(destination, value)
	if taking {
		ios_runtime.swift_unknown_weak.delete(source)
		unsafe { *(&u64(source)) = 0 }
	}
	return destination
}

fn swift_unknown_weak_load_checked(location u64, taking bool) !u64 {
	swift_unknown_weak_address(location)!
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut value := swift_unknown_weak_live_locked(swift_unknown_weak_read_locked(location)!)!
	if !swift_unknown_weak_immortal_locked(value) {
		if swift_unknown_weak_native_locked(value) {
			// Retain under the same lock as final-release invalidation. Never
			// release/call user destructors while holding this lock.
			swift_buffer_refs(value, 1)!
		} else {
			header := ios_runtime.objects[value] or { return swift_unknown_weak_failure() }
			if C.ios_ref_try_retain(unsafe { &header.refs }) == 0 { value = 0 }
		}
	}
	if taking {
		ios_runtime.swift_unknown_weak.delete(location)
		unsafe { *(&u64(location)) = 0 }
	}
	return value
}

fn swift_unknown_weak_destroy_checked(location u64) ! {
	swift_unknown_weak_address(location)!
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	swift_unknown_weak_read_locked(location)!
	ios_runtime.swift_unknown_weak.delete(location)
	unsafe { *(&u64(location)) = 0 }
}

fn swift_unknown_weak_initialize(destination u64, object u64) u64 {
	return swift_unknown_weak_update_checked(destination, 0, object, .initialize) or { panic(err) }
}
fn swift_unknown_weak_assign(destination u64, object u64) u64 {
	return swift_unknown_weak_update_checked(destination, 0, object, .assign) or { panic(err) }
}
fn swift_unknown_weak_copy_initialize(destination u64, source u64) u64 {
	return swift_unknown_weak_update_checked(destination, source, 0, .copy_initialize) or { panic(err) }
}
fn swift_unknown_weak_take_initialize(destination u64, source u64) u64 {
	return swift_unknown_weak_update_checked(destination, source, 0, .take_initialize) or { panic(err) }
}
fn swift_unknown_weak_copy_assign(destination u64, source u64) u64 {
	return swift_unknown_weak_update_checked(destination, source, 0, .copy_assign) or { panic(err) }
}
fn swift_unknown_weak_take_assign(destination u64, source u64) u64 {
	return swift_unknown_weak_update_checked(destination, source, 0, .take_assign) or { panic(err) }
}
fn swift_unknown_weak_load(location u64) u64 {
	return swift_unknown_weak_load_checked(location, false) or { panic(err) }
}
fn swift_unknown_weak_take(location u64) u64 {
	return swift_unknown_weak_load_checked(location, true) or { panic(err) }
}
fn swift_unknown_weak_destroy(location u64) {
	swift_unknown_weak_destroy_checked(location) or { panic(err) }
}

fn swift_unknown_weak_stop() {
	if ios_runtime.swift_unknown_weak.len != 0 { panic('iOS: Swift weak references still initialized at shutdown') }
	unsafe { ios_runtime.swift_unknown_weak.free() }
}

fn swift_unknown_weak_symbol(symbol string) ?u64 {
	return match symbol {
		'_swift_unknownObjectWeakInit' { u64(unsafe { voidptr(swift_unknown_weak_initialize) }) }
		'_swift_unknownObjectWeakAssign' { u64(unsafe { voidptr(swift_unknown_weak_assign) }) }
		'_swift_unknownObjectWeakLoadStrong' { u64(unsafe { voidptr(swift_unknown_weak_load) }) }
		'_swift_unknownObjectWeakTakeStrong' { u64(unsafe { voidptr(swift_unknown_weak_take) }) }
		'_swift_unknownObjectWeakDestroy' { u64(unsafe { voidptr(swift_unknown_weak_destroy) }) }
		'_swift_unknownObjectWeakCopyInit' { u64(unsafe { voidptr(swift_unknown_weak_copy_initialize) }) }
		'_swift_unknownObjectWeakTakeInit' { u64(unsafe { voidptr(swift_unknown_weak_take_initialize) }) }
		'_swift_unknownObjectWeakCopyAssign' { u64(unsafe { voidptr(swift_unknown_weak_copy_assign) }) }
		'_swift_unknownObjectWeakTakeAssign' { u64(unsafe { voidptr(swift_unknown_weak_take_assign) }) }
		else { return none }
	}
}
