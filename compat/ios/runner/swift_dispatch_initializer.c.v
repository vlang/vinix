// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftDispatchInitializerFailure {}
fn (_ &SwiftDispatchInitializerFailure) msg() string { return 'iOS: Swift DispatchQueue initializer requires an active runtime, a supported UTF-8 label, unspecified QoS, empty attributes, inherited autorelease frequency and a nil or registered target' }
fn (_ &SwiftDispatchInitializerFailure) code() int { return 1 }
__global swift_dispatch_initializer_failure_value = SwiftDispatchInitializerFailure{}
fn swift_dispatch_initializer_failure() IError { return unsafe { &swift_dispatch_initializer_failure_value } }

// The allocating Swift initializer consumes both String words (x0/x1) and
// Optional<DispatchQueue> (x5); QoS/attributes/autorelease are borrowed pointers
// in x2..x4. The metatype in x20 is unused. Validate before consuming ownership.
fn swift_dispatch_initializer_checked(first u64, second u64, qos u64, attributes u64, autorelease u64, target u64) !u64 {
	swift_dispatch_main_queue_checked()!
	if target != 0 { swift_dispatch_async_queue_checked(target)! }
	if qos == 0 || attributes == 0 || autorelease == 0 { return swift_dispatch_initializer_failure() }
	if unsafe { *(&u8(qos)) } != 5 || read64(qos + 8) != 0
		|| read64(attributes) != 0 || unsafe { *(&u8(autorelease)) } != 0 {
		return swift_dispatch_initializer_failure()
	}
	buffer := swift_cstring_buffer_checked(first, second)!
	// utf8CString owns independent storage. Queue creation copies its C label
	// and retains the target before the initializer releases its consumed inputs.
	swift_bridge_release(second)
	queue := darwin_dispatch_queue_create_with_target(&char(buffer + 32), 0, target)
	swift_release(buffer)
	objc_release(target)
	return queue
}

fn swift_dispatch_initializer(first u64, second u64, qos u64, attributes u64, autorelease u64, target u64) u64 {
	return swift_dispatch_initializer_checked(first, second, qos, attributes, autorelease, target) or { panic(err) }
}

fn swift_dispatch_initializer_build(base u64) {
	swift_dispatch_bridge(base + 1056, 0xd503201f, 0xd503201f,
		u64(unsafe { voidptr(swift_dispatch_initializer) }))
}
