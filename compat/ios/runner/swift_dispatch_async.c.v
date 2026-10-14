// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftDispatchAsyncFailure {}
fn (_ &SwiftDispatchAsyncFailure) msg() string { return 'iOS: Swift DispatchQueue.async requires an active registered queue, nil group, unspecified QoS, empty flags and a nonnil block' }
fn (_ &SwiftDispatchAsyncFailure) code() int { return 1 }
__global swift_dispatch_async_failure_value = SwiftDispatchAsyncFailure{}
fn swift_dispatch_async_failure() IError { return unsafe { &swift_dispatch_async_failure_value } }

fn swift_dispatch_async_queue_checked(identity u64) ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_dispatch_flags_retired
		|| system_data == unsafe { nil } || dispatch_runtime == unsafe { nil } {
		return swift_dispatch_async_failure()
	}
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	if dispatch_runtime.stopping || identity !in dispatch_runtime.queues {
		return swift_dispatch_async_failure()
	}
}

// The supplied Swift caller passes group/QoS/flags/block in x0..x3, with the
// borrowed queue in x20. Only the native direct-dispatch profile is supported.
// Check it before copying a block, running capture helpers or adding any job.
fn swift_dispatch_async_checked(group u64, qos u64, flags u64, block u64, queue u64) ! {
	swift_dispatch_async_queue_checked(queue)!
	if group != 0 || qos == 0 || flags == 0 || block == 0 { return swift_dispatch_async_failure() }
	if unsafe { *(&u8(qos)) } != 5 || read64(qos + 8) != 0 || read64(flags) != 0 {
		return swift_dispatch_async_failure()
	}
	// All runtime/scheduler locks have been released. The existing dispatcher
	// promotes stack blocks once, retains heap blocks, runs helpers unlocked,
	// and releases the queued ownership on execution or shutdown cancellation.
	darwin_dispatch_async(queue, block)
}

fn swift_dispatch_async(group u64, qos u64, flags u64, block u64, queue u64) {
	swift_dispatch_async_checked(group, qos, flags, block, queue) or { panic(err) }
}

fn swift_dispatch_async_build(base u64) {
	swift_dispatch_bridge(base + 800, 0xaa1403e4, 0xd503201f,
		u64(unsafe { voidptr(swift_dispatch_async) })) // mov x4, x20; ordinary V tail call.
}
