// SPDX-License-Identifier: GPL-2.0-or-later
module main

const swift_static_object_immortal = u64(0x80000004ffffffff)
const swift_static_object_limit = 1024

struct SwiftStaticObjectFailure {}

fn (_ &SwiftStaticObjectFailure) msg() string {
	return 'iOS: invalid or unsupported Swift static object initialization'
}

fn (_ &SwiftStaticObjectFailure) code() int { return 1 }

__global swift_static_object_failure_value = SwiftStaticObjectFailure{}

fn swift_static_object_failure() IError { return unsafe { &swift_static_object_failure_value } }

// Called under the runtime lock. Membership, never a header-shaped bit pattern,
// grants immortal ARC; unknown pointers must be rejected before any header read.
fn swift_static_object_registered_locked(object u64) bool {
	for i in 0 .. ios_runtime.swift_static_object_count {
		if ios_runtime.swift_static_objects[i] == object { return true }
	}
	return false
}

fn swift_static_initialize_checked(metadata u64, object u64) !u64 {
	if object < 8 || object & 7 != 0 || object > ~u64(0) - 16 {
		return swift_static_object_failure()
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return swift_static_object_failure()
	}
	if swift_static_object_registered_locked(object) { return object }
	if ios_runtime.swift_static_object_count == swift_static_object_limit
		|| object in ios_runtime.swift_heap || object in ios_runtime.swift_arrays
		|| object in ios_runtime.swift_buffers || object in ios_runtime.swift_strings
		|| object in ios_runtime.objects || object in ios_runtime.classes
		|| object in ios_runtime.constants || object in ios_runtime.block_refs {
		return swift_static_object_failure()
	}
	// The image supplies a writable, aligned once word immediately before the
	// header, initially zero, and keeps the storage alive through runtime drain.
	// Serialize initialization and registration together. Publication matches
	// swift_once; Darwin's -1 completed token also accepts preinitialized storage.
	token := unsafe { &u64(object - 8) }
	completed := C.ios_load_pointer(token)
	if completed == 0 {
		// Native Swift does not dereference metadata here, including nil metadata.
		unsafe {
			*(&u64(object)) = metadata
			*(&u64(object + 8)) = swift_static_object_immortal
		}
		C.ios_store_pointer(token, swift_once_done)
	} else if completed != swift_once_done && completed != ~u64(0) {
		return swift_static_object_failure()
	} else if read64(object + 8) != swift_static_object_immortal {
		return swift_static_object_failure()
	}
	ios_runtime.swift_static_objects[ios_runtime.swift_static_object_count] = object
	ios_runtime.swift_static_object_count++
	return object
}

fn swift_static_initialize(metadata u64, object u64) u64 {
	return swift_static_initialize_checked(metadata, object) or { panic(err) }
}

fn swift_static_objects_stop() {
	// Only borrowed addresses remain. All users have drained; do not read,
	// rewrite, destroy or free any part of the application's static storage.
	for i in 0 .. ios_runtime.swift_static_object_count { ios_runtime.swift_static_objects[i] = 0 }
	ios_runtime.swift_static_object_count = 0
}
