// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftPartialClassFailure {}
fn (_ &SwiftPartialClassFailure) msg() string { return 'iOS: unsupported Swift partial class deallocation, hierarchy or ownership' }
fn (_ &SwiftPartialClassFailure) code() int { return 1 }
__global swift_partial_class_failure_value = SwiftPartialClassFailure{}
fn swift_partial_class_failure() IError { return unsafe { &swift_partial_class_failure_value } }

// True delegates one ordinary ObjC release outside the registry lock. False
// means nil or an already reclaimed native owner. Never walk an unvalidated
// superclass chain or dispatch the failed class's deallocating destructor.
fn swift_partial_class_dispose_checked(owner u64, metadata u64, size u64, mask u64) !bool {
	if owner == 0 { return false }
	if owner & 0x8000000000000007 != 0 { return swift_partial_class_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return swift_partial_class_failure() }
	if storage := ios_runtime.swift_heap[owner] {
		// This profile has no initialized subclass ivars above the requested
		// boundary. Borrow the exact registered allocation layout and identity.
		if storage.deiniting || metadata != storage.metadata || size != storage.size
			|| mask != storage.mask || read64(owner) != metadata
			|| C.ios_load_pointer(unsafe { &u64(owner + 8) }) != 3 { return swift_partial_class_failure() }
		kind := read64(metadata)
		if (kind != 0 && kind <= 0x7ff) || read64(metadata + 32) & 2 == 0
			|| read32(metadata + 40) & 2 == 0 || read32(metadata + 44) != 0 { return swift_partial_class_failure() }
		// No ivar destroyer or destructor is called when the boundary is the
		// allocated class itself. Existing unique-owner deallocation frees it.
		swift_heap_deallocate_checked(owner, size, mask, true) or { return swift_partial_class_failure() }
		return false
	}
	mut cls := u64(0)
	if header := ios_runtime.objects[owner] {
		if header.destroyed || header.destroying || header.releasing
			|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 { return swift_partial_class_failure() }
		cls = header.cls
		if read64(owner) != cls { return swift_partial_class_failure() }
	} else if owner in ios_runtime.constants {
		cls = read64(owner)
	} else {
		return swift_partial_class_failure()
	}
	info := ios_runtime.classes[cls] or { return swift_partial_class_failure() }
	if info.meta || (info.dynamic && !info.registered) || read64(cls + 32) & 2 != 0 { return swift_partial_class_failure() }
	// Native's pure-ObjC fast path ignores metadata, size and alignment, even
	// for shared or immutable placeholder objects. No class lookup callback.
	return true
}
fn swift_partial_class_checked(owner u64, metadata u64, size u64, mask u64) ! {
	if swift_partial_class_dispose_checked(owner, metadata, size, mask)! { objc_release(owner) }
}
fn swift_partial_class(owner u64, metadata u64, size u64, mask u64) {
	swift_partial_class_checked(owner, metadata, size, mask) or { panic(err) }
}
