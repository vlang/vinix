// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftDispatchMainFailure {}
fn (_ &SwiftDispatchMainFailure) msg() string { return 'iOS: Swift DispatchQueue.main requires an active main queue' }
fn (_ &SwiftDispatchMainFailure) code() int { return 1 }
__global swift_dispatch_main_failure_value = SwiftDispatchMainFailure{}
fn swift_dispatch_main_failure() IError { return unsafe { &swift_dispatch_main_failure_value } }

fn swift_dispatch_main_queue_checked() !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_dispatch_flags_retired
		|| system_data == unsafe { nil } || dispatch_runtime == unsafe { nil } {
		return swift_dispatch_main_failure()
	}
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	if dispatch_runtime.stopping { return swift_dispatch_main_failure() }
	identity := darwin_dispatch_get_main_queue()
	queue := dispatch_runtime.queues[identity] or { return swift_dispatch_main_failure() }
	if !queue.main || !queue.immortal { return swift_dispatch_main_failure() }
	return identity
}

// Native Swift returns +1 through objc_retainAutoreleasedReturnValue. The
// canonical Vinix main queue is immortal; use the shared ObjC ownership path.
fn swift_dispatch_main_queue() u64 {
	identity := swift_dispatch_main_queue_checked() or { panic(err) }
	return objc_retain(identity)
}

fn swift_dispatch_main_build(base u64) {
	// Swift returns the object directly in x0; x8 and Swift context are unused.
	swift_dispatch_bridge(base + 768, 0xd503201f, 0xd503201f,
		u64(unsafe { voidptr(swift_dispatch_main_queue) }))
}
