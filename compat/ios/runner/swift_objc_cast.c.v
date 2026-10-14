// SPDX-License-Identifier: GPL-2.0-or-later
module main

// This entry takes a raw ObjC class, not a Swift wrapper metadata address.
// Both matching and failed conditional casts borrow the input reference.
fn swift_dynamic_cast_objc_class_checked(owner u64, target u64) !u64 {
	// Native nil casts return nil before inspecting the target.
	if owner == 0 { return 0 }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return swift_dynamic_cast_failure() }
	C.ios_objc_initialize_lock()
	info := ios_runtime.classes[target] or { C.ios_objc_initialize_unlock(); return swift_dynamic_cast_failure() }
	valid := !info.meta && (!info.dynamic || info.registered) && target != cf_error_type_id()
		&& read64(target + 32) & 2 == 0
	C.ios_objc_initialize_unlock()
	if !valid { return swift_dynamic_cast_failure() }
	return if swift_dynamic_cast_class_checked(owner,0,target)! { owner } else { u64(0) }
}
fn swift_dynamic_cast_objc_class(owner u64, target u64) u64 {
	return swift_dynamic_cast_objc_class_checked(owner,target) or { panic(err) }
}
