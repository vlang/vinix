// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Swift's no-current-task path uses one shared fallback allocator, including
// across threads. Real task creation/current-task switching remain unsupported;
// when added, their task-private allocators must follow the active task.
// Payloads are uninitialized, 16-byte aligned and freed strictly in LIFO order.
// The private 16-byte header belongs to Vinix, never to the caller's payload.
fn swift_task_allocate_checked(size u64) !u64 {
	$if !arm64 { return error('iOS: Swift task allocation requires ARM64') }
	if ios_runtime == unsafe { nil } { return error('iOS: Swift task allocation outside runtime lifetime') }
	// Round up and add the header without unsigned or signed allocation overflow.
	if size > 0x7fffffffffffffe0 { return error('iOS: Swift task allocation size overflow') }
	rounded := (size + 15) & ~u64(15)
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_concurrency_retired { return error('iOS: Swift task allocation outside runtime lifetime') }
	if ios_runtime.swift_task_alloc_count == u64(-1) { return error('iOS: Swift task allocation count overflow') }
	// An ordinary address-taken V local would be promoted to the heap.
	pointer := unsafe { &u64(C.__builtin_alloca(8)) }
	unsafe { *pointer = 0 }
	if C.posix_memalign(unsafe { voidptr(pointer) }, 16, usize(16 + rounded)) != 0 {
		return error('iOS: cannot allocate Swift task storage')
	}
	node := unsafe { *pointer }
	unsafe {
		*(&u64(node)) = ios_runtime.swift_task_alloc_top
		*(&u64(node + 8)) = rounded
	}
	ios_runtime.swift_task_alloc_top = node
	ios_runtime.swift_task_alloc_count++
	return node + 16
}

fn swift_task_allocate(size u64) u64 {
	return swift_task_allocate_checked(size) or { panic(err) }
}

fn swift_task_deallocate_checked(pointer u64) ! {
	if ios_runtime == unsafe { nil } { return error('iOS: Swift task deallocation outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_concurrency_retired { return error('iOS: Swift task deallocation outside runtime lifetime') }
	node := ios_runtime.swift_task_alloc_top
	// Compare against our registered top before reading any supplied address.
	if node == 0 || pointer != node + 16 || ios_runtime.swift_task_alloc_count == 0 {
		return error('iOS: Swift task deallocation is not the most recent allocation')
	}
	ios_runtime.swift_task_alloc_top = read64(node)
	ios_runtime.swift_task_alloc_count--
	C.free(unsafe { voidptr(node) })
}

fn swift_task_deallocate(pointer u64) {
	swift_task_deallocate_checked(pointer) or { panic(err) }
}

fn swift_task_allocator_drain_checked() ! {
	if ios_runtime == unsafe { nil } { return error('iOS: Swift task allocator outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_task_alloc_top != 0 || ios_runtime.swift_task_alloc_count != 0 {
		return error('iOS: Swift task allocations have not drained')
	}
}

fn swift_task_alloc_symbol(symbol string) !u64 {
	$if !arm64 { return error('iOS: Swift task allocation requires ARM64') }
	if ios_runtime == unsafe { nil } { return error('iOS: Swift task allocator outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_concurrency_retired { return error('iOS: Swift task allocator outside runtime lifetime') }
	// One scalar x0 argument/result uses the ordinary ARM64 ABI. Callee-saved
	// x20 (Self), x21 (error), x22 (async context) remain borrowed and untouched.
	return match symbol {
		'_swift_task_alloc' { u64(voidptr(swift_task_allocate)) }
		'_swift_task_dealloc' { u64(voidptr(swift_task_deallocate)) }
		else { return error('iOS: unsupported Swift task allocation symbol') }
	}
}
