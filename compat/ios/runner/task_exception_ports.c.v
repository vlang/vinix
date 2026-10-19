// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <mach/task.h>
	fn C.mach_task_self() u32
	fn C.task_get_exception_ports(u32, u32, voidptr, voidptr, voidptr, voidptr, voidptr) i32
}
type TaskExceptionNativeQuery = fn (u32, u32, voidptr, voidptr, voidptr, voidptr, voidptr) i32

// Caller holds the task namespace lock. Unknown native Mac names remain
// native destinations; compatibility receive queues cannot serve typed MIG.
fn task_exception_destination(task u32) i32 {
	if system_data != unsafe { nil } {
		if task == system_data.task_self { return 0 }
		port := mach_receive_find(task)
		if port != unsafe { nil } {
			return if port.receive && port.refs != 0 { i32(46) } else { i32(0x10000003) }
		}
		if mach_host_live(task) || mach_semaphore_find(task) != unsafe { nil }
			|| mach_memory_find(task) != unsafe { nil } { return 4 }
		$if linux {
			mach_threads_refresh()
			worker := mach_thread_find(task)
			if worker != unsafe { nil } && !worker.dead { return 4 }
		}
	}
	$if macos { return 0 }
	return i32(0x10000003)
}

fn darwin_task_get_exception_ports(task u32, mask u32, masks voidptr, count voidptr, handlers voidptr, behaviors voidptr, flavors voidptr) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.ios_mach_threads_lock()
	result := task_exception_destination(task)
	mut destination := task
	$if macos {
		if system_data != unsafe { nil } && task == system_data.task_self { destination = C.mach_task_self() }
	}
	C.ios_mach_threads_unlock()
	if result != 0 { return result }
	$if macos {
		native_query := unsafe { TaskExceptionNativeQuery(voidptr(C.task_get_exception_ports)) }
		return native_query(destination, mask, masks, count, handlers, behaviors, flavors)
	}
	$if linux {
		if mask & ~u32(0x3ffe) != 0 { return 4 }
		// No Mach handlers can be installed on Vinix yet. Query the initial
		// unset task actions: one null/zero group for every requested bit.
		// masksCnt is output-only, including when its incoming value is zero.
		words := [mask, u32(mask != 0), 0]!
		if mask != 0 { C.memcpy(masks, unsafe { voidptr(&words[0]) }, 4) }
		C.memcpy(count, unsafe { voidptr(&words[1]) }, 4)
		if mask != 0 {
			// Native MIG copies masks, count, handlers, behaviors, then flavors.
			// Keep that order when caller-owned output spans overlap.
			C.memcpy(handlers, unsafe { voidptr(&words[2]) }, 4)
			C.memcpy(behaviors, unsafe { voidptr(&words[2]) }, 4)
			C.memcpy(flavors, unsafe { voidptr(&words[2]) }, 4)
		}
		return 0
	}
}
