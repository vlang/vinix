// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftSetDeallocatingFailure {}
fn (_ &SwiftSetDeallocatingFailure) msg() string { return 'iOS: unsupported Swift setDeallocating object or reference count' }
fn (_ &SwiftSetDeallocatingFailure) code() int { return 1 }
__global swift_set_deallocating_failure_value = SwiftSetDeallocatingFailure{}
fn swift_set_deallocating_failure() IError { return unsafe { &swift_set_deallocating_failure_value } }

fn swift_set_deallocating_checked(owner u64) ! {
	if owner == 0 || owner & 7 != 0 || owner > ~u64(0) - 16 {
		return swift_set_deallocating_failure()
	}
	// Like initStackObject, the caller supplies a live writable header. Swift
	// requires exactly one strong reference and exclusive access during this
	// transition. Borrowed frame headers have two unowned refs (bits 5); only
	// registered heap objects support the one-unowned-ref profile (bits 3).
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	bits := C.ios_load_pointer(unsafe { &u64(owner + 8) })
	mut heap := false
	if ios_runtime != unsafe { nil } {
		if mut storage := ios_runtime.swift_heap[owner] {
			if storage.deiniting || bits != 3 { return swift_set_deallocating_failure() }
			storage.deiniting = true
			ios_runtime.swift_heap[owner] = storage
			heap = true
		} else if owner in ios_runtime.swift_buffers || owner in ios_runtime.swift_strings
			|| owner in ios_runtime.swift_arrays || swift_task_find_locked(owner) != 0 {
			return swift_set_deallocating_failure()
		}
	}
	if !heap && bits != 5 { return swift_set_deallocating_failure() }
	// This consumes the final strong reference and sets IsDeiniting. The caller
	// destroys stored properties and, for heap storage, deallocates afterward.
	// Do not dispatch a destructor, free bytes, or register borrowed frame memory.
	C.ios_store_pointer(unsafe { &u64(owner + 8) }, bits | 0x100000000)
	if heap { swift_unknown_weak_retire_locked(owner) }
}

fn swift_set_deallocating(owner u64) {
	swift_set_deallocating_checked(owner) or { panic(err) }
}
