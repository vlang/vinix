// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn swift_concurrency_emit(code u64) {
	// Actor.unownedExecutor: metadata x0, table x1, borrowed actor x20.
	// Word 0 is the conformance descriptor; word 1 is the getter. Tail-call
	// that witness with the metadata, table and context unchanged. Its two
	// executor words return in x0/x1. Vinix uses ordinary ARM64 code pointers.
	write32(code, 0xf9400430) // ldr x16,[x1,#8]
	write32(code + 4, 0xd61f0200) // br x16
	// TaskPriority is not frozen: the getter borrows indirect Self in x20.
	// Read exactly one UInt8, including at a protected page boundary.
	write32(code + 32, 0x39400280) // ldrb w0,[x20]
	write32(code + 36, 0xd65f03c0)
}

fn swift_concurrency_entry(offset u64) !u64 {
	$if !arm64 { return error('iOS: Swift concurrency entries require ARM64') }
	if ios_runtime == unsafe { nil } { return error('iOS: Swift concurrency outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_concurrency_retired { return error('iOS: Swift concurrency outside runtime lifetime') }
	if ios_runtime.swift_concurrency_code == 0 {
		page := usize(C.getpagesize())
		code := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if code == unsafe { voidptr(-1) } { return error('iOS: cannot allocate Swift concurrency entries') }
		swift_concurrency_emit(u64(code))
		C.__builtin___clear_cache(code, unsafe { voidptr(u64(code) + 40) })
		if C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) != 0 {
			if C.munmap(code, page) != 0 { panic('iOS: cannot retire unsealed Swift concurrency entries') }
			return error('iOS: cannot seal Swift concurrency entries')
		}
		ios_runtime.swift_concurrency_code = u64(code)
	}
	return ios_runtime.swift_concurrency_code + offset
}

fn swift_concurrency_symbol(symbol string) !u64 {
	if symbol in ['_$sScMMa','_$sScMMn','_$sScM6sharedScMvgZ'] {
		return swift_main_actor_symbol(symbol)
	}
	if symbol in ['_swift_task_create', '_swift_task_getCurrent', '_swift_job_run', '_swift_task_switch'] {
		return swift_task_create_symbol(symbol)
	}
	if symbol in ['_swift_task_alloc', '_swift_task_dealloc'] {
		return swift_task_alloc_symbol(symbol)
	}
	if symbol in ['_$sScPMa', '_$sScPMn', '_$sScPN'] {
		base := swift_task_priority_arena()!
		if symbol == '_$sScPMa' { return base }
		return base + u64(C.getpagesize()) + if symbol == '_$sScPMn' { u64(160) } else { u64(16) }
	}
	offset := match symbol {
		'_$sScA15unownedExecutorScevgTj' { u64(0) }
		'_$sScP8rawValues5UInt8Vvg' { u64(32) }
		else { return error('iOS: Swift concurrency symbol is not implemented: ${symbol}') }
	}
	return swift_concurrency_entry(offset)
}

fn swift_concurrency_stop() {
	// Called under the runtime lock after workers and callbacks have drained.
	swift_task_allocator_drain_checked() or { panic(err) }
	swift_tasks_stop()
	swift_task_priority_stop()
	if ios_runtime.swift_concurrency_code != 0 {
		if C.munmap(unsafe { voidptr(ios_runtime.swift_concurrency_code) }, usize(C.getpagesize())) != 0 {
			panic('iOS: cannot retire Swift concurrency entries')
		}
		ios_runtime.swift_concurrency_code = 0
	}
	ios_runtime.swift_concurrency_retired = true
}
