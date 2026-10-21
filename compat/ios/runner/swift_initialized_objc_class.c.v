// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftInitializedObjCClassFailure {}
fn (_ &SwiftInitializedObjCClassFailure) msg() string { return 'iOS: unsupported Swift initialized Objective-C class or lifetime' }
fn (_ &SwiftInitializedObjCClassFailure) code() int { return 1 }
__global swift_initialized_objc_class_failure_value = SwiftInitializedObjCClassFailure{}
fn swift_initialized_objc_class_failure() IError { return unsafe { &swift_initialized_objc_class_failure_value } }

fn swift_initialized_objc_class_validate(cls u64) ! {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return swift_initialized_objc_class_failure() }
	mut current := cls
	for _ in 0..128 {
		if current == 0 { return }
		// Validate registration before reading borrowed class bytes. Swift
		// wrappers, metaclasses and classes requiring Swift realization are
		// distinct from registered ordinary Objective-C class objects.
		info := ios_runtime.classes[current] or { return swift_initialized_objc_class_failure() }
		if info.meta || (info.dynamic && !info.registered) || current & 7 != 0 || current > ~u64(0) - 40
			|| read64(current + 32) & 2 != 0 { return swift_initialized_objc_class_failure() }
		meta := ios_runtime.classes[read64(current)] or { return swift_initialized_objc_class_failure() }
		if !meta.meta { return swift_initialized_objc_class_failure() }
		current = info.parent
	}
	return swift_initialized_objc_class_failure()
}
fn swift_initialized_objc_class_checked(cls u64) !u64 {
	// Native nil messaging returns nil without requiring a running runtime.
	if cls == 0 { return u64(0) }
	swift_initialized_objc_class_validate(cls)!
	// Reuse the Objective-C lifecycle's superclass-first, once-only and
	// same-thread reentrant initialization. Registered class storage and IMPs
	// remain borrowed until callers have drained.
	objc_initialize(cls)
	C.ios_objc_initialize_lock()
	method := native_method(read64(cls), 'self')
	C.ios_objc_initialize_unlock()
	// +self is dispatched on every call, including already-initialized types.
	// Its result is ignored even when an override returns another object.
	if method != 0 { unsafe { ObjInit(voidptr(method))(cls, c'self') } }
	return cls
}
// Ordinary C ABI: one class pointer in x0, the original class pointer in x0.
fn swift_initialized_objc_class(cls u64) u64 {
	return swift_initialized_objc_class_checked(cls) or { panic(err) }
}
