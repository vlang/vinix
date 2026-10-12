// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn swift_task_switch_checked(context u64, continuation u64, identity u64, implementation u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return error('iOS: Swift task switch outside runtime lifetime')
	}
	// Supported jobs use the generic executor, without task executor preference.
	// Native switches to that same executor resume immediately.
	if identity != 0 || implementation != 0 {
		return error('iOS: Swift task switch to actor or custom executor is not implemented')
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	owner := swift_task_current()
	if owner == 0 || swift_task_find_locked(owner) == 0 {
		return error('iOS: Swift task switch without current task')
	}
	if unsafe { (&SwiftTaskState(owner + 80)).phase } != 2 {
		return error('iOS: Swift task switch requires a running task')
	}
	if context < 8 || context & 7 != 0 || context > 0x0000fffffffffff8
		|| continuation < 4 || continuation & 3 != 0 || continuation > 0x0000fffffffffffc {
		return error('iOS: invalid Swift task switch continuation')
	}
	// Context is opaque: the continuation may accept protected storage. Do not
	// read it, park the task, change references, or update saved resume slots.
	return continuation
}

fn swift_task_switch_prepare(context u64, continuation u64, identity u64, implementation u64) u64 {
	return swift_task_switch_checked(context, continuation, identity, implementation) or { panic(err) }
}
