// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftStackInitializationFailure {}
fn (_ &SwiftStackInitializationFailure) msg() string { return 'iOS: invalid Swift stack object header storage' }
fn (_ &SwiftStackInitializationFailure) code() int { return 1 }
__global swift_stack_initialization_failure_value = SwiftStackInitializationFailure{}
fn swift_stack_initialization_failure() IError { return unsafe { &swift_stack_initialization_failure_value } }

fn swift_stack_initialize_checked(metadata u64, storage u64) !u64 {
	if storage == 0 || storage & 7 != 0 || storage > ~u64(0) - 16 {
		return swift_stack_initialization_failure()
	}
	// The caller supplies a fresh writable header and owns its entire lifetime.
	// Metadata is opaque here, including nil; native init does not read it.
	// Two unowned refs prevent native final-release deallocation of stack bytes.
	unsafe {
		*(&u64(storage)) = metadata
		*(&u64(storage + 8)) = 5
	}
	return storage
}

fn swift_stack_initialize(metadata u64, storage u64) u64 {
	return swift_stack_initialize_checked(metadata, storage) or { panic(err) }
}
