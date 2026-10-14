// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftErrorBridgeFailure {}
fn (_ &SwiftErrorBridgeFailure) msg() string { return 'iOS: Swift NSError bridge requires a live registered CFError or ObjC NSError; native Swift error boxes are not implemented' }
fn (_ &SwiftErrorBridgeFailure) code() int { return 1 }
__global swift_error_bridge_failure_value = SwiftErrorBridgeFailure{}
fn swift_error_bridge_failure() IError { return unsafe { &swift_error_bridge_failure_value } }

// SDK: __owned Error -> AnyObject. A toll-free NSError is already the result:
// transfer the incoming reference, preserving identity and its owned fields.
// Native Swift error boxes need separate lazy domain/code/userInfo witnesses
// and cache publication; a general Swift heap owner is not an NSError here.
fn swift_error_bridge_checked(owner u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| owner == 0 || owner & 7 != 0 { return swift_error_bridge_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[owner] or { return swift_error_bridge_failure() }
	if header.releasing || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 {
		return swift_error_bridge_failure()
	}
	if read64(owner) != header.cls { return swift_error_bridge_failure() }
	mut cls := header.cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[cls] or { return swift_error_bridge_failure() }
		if info.meta || (info.dynamic && !info.registered) || read64(cls + 32) & 2 != 0 {
			return swift_error_bridge_failure()
		}
		if cls == cf_error_type_id() || cls == ios_runtime.names['NSError'] { return owner }
		cls = info.parent
		if cls == 0 { return swift_error_bridge_failure() }
	}
	return swift_error_bridge_failure()
}

fn swift_error_bridge(owner u64) u64 {
	return swift_error_bridge_checked(owner) or { panic(err) }
}
