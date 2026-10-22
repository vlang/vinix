// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftDispatchSyncFailure {}
fn (_ &SwiftDispatchSyncFailure) msg() string { return 'iOS: Swift DispatchQueue.sync requires an active registered queue, closure and supported result value witnesses' }
fn (_ &SwiftDispatchSyncFailure) code() int { return 1 }
__global swift_dispatch_sync_failure_value = SwiftDispatchSyncFailure{}
fn swift_dispatch_sync_failure() IError { return unsafe { &swift_dispatch_sync_failure_value } }

type SwiftDispatchSyncCall = fn (u64, u64, u64) u64
struct SwiftDispatchSyncContext {
	function u64
	context u64
	output u64
	@[required]
	call SwiftDispatchSyncCall
mut:
	error u64
}
fn swift_dispatch_sync_body(context voidptr) {
	mut state := unsafe { &SwiftDispatchSyncContext(context) }
	state.error = state.call(state.function, state.context, state.output)
}

// Swift generic sync: function/context/Result metadata in x0..x2, borrowed
// queue in x20, indirect result in x8 and owned thrown error in x21. The
// synchronous job borrows this frame until its callback completes, including
// when the main thread executes a background submitter's main-queue job.
fn swift_dispatch_sync_checked(function u64, context u64, metadata u64, queue u64, output u64) !u64 {
	// Reject an inactive/retired queue before inspecting any caller storage.
	swift_dispatch_async_queue_checked(queue) or { return swift_dispatch_sync_failure() }
	if function == 0 || function & 3 != 0 { return swift_dispatch_sync_failure() }
	layout := swift_sequence_value_checked(metadata) or { return swift_dispatch_sync_failure() }
	if layout.size != 0 && (output == 0 || output & (layout.alignment - 1) != 0) {
		return swift_dispatch_sync_failure()
	}
	base := u64(C.__builtin_alloca(usize(layout.size + layout.alignment)))
	temporary := (base + layout.alignment - 1) & ~(layout.alignment - 1)
	copy_base := u64(C.__builtin_alloca(usize(layout.size + layout.alignment)))
	copy := (copy_base + layout.alignment - 1) & ~(layout.alignment - 1)
	mut state := SwiftDispatchSyncContext{ function: function, context: context, output: temporary,
		call: unsafe { SwiftDispatchSyncCall(voidptr(swift_dispatch_flags_arena_checked()! + 992)) } }
	// The scheduler retains the queue, preserves ordering and queue-specific
	// context, and invokes the closure with all registry/scheduler locks released.
	darwin_dispatch_sync_f(queue, voidptr(&state), swift_dispatch_sync_body)
	if state.error != 0 { return state.error }
	// Match native Optional<Result> staging: copy the initialized result, destroy
	// the original and take the copy into the caller. A throwing closure leaves
	// its result uninitialized; neither destroy it nor touch the caller's output.
	copy_value := unsafe { SwiftSequenceCopy(voidptr(layout.copy)) }
	destroy := unsafe { SwiftSequenceDestroy(voidptr(layout.destroy)) }
	take := unsafe { SwiftSequenceCopy(voidptr(layout.take)) }
	copy_value(copy, temporary, metadata)
	destroy(temporary, metadata)
	take(output, copy, metadata)
	return 0
}
fn swift_dispatch_sync(function u64, context u64, metadata u64, queue u64, output u64) u64 {
	return swift_dispatch_sync_checked(function, context, metadata, queue, output) or { panic(err) }
}

fn swift_dispatch_sync_build(base u64) {
	// Swift -> C. C preserves the incoming x21 on success; replace it only
	// with a nonzero owned error. Preserve the caller's borrowed queue in x20.
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e3, 0xaa0803e4, 0x580000f0,
		0xd63f0200, 0xb4000040, 0xaa0003f5, 0xa8c17bfd, 0xd65f03c0, 0xd503201f]! {
		write32(base + 928 + u64(i * 4), op)
	}
	unsafe { *(&u64(base + 968)) = u64(voidptr(swift_dispatch_sync)) }
	// C -> Swift throwing closure. No arguments, context x20, indirect result
	// x8, initially clear x21; capture its error and restore all C callee saves.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0,
		0xaa0103f4, 0xaa0203e8, 0xaa1f03f5, 0xd63f0200, 0xaa1503e0,
		0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(base + 992 + u64(i * 4), op)
	}
}
