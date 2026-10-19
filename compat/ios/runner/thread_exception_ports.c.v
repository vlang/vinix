// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <mach/thread_act.h>
	fn C.thread_get_exception_ports(u32, u32, voidptr, voidptr, voidptr, voidptr, voidptr) i32
}

// Caller holds the shared Mach namespace lock. A thread RPC requires a live
// send right to a thread; compatibility receive queues cannot serve typed MIG.
fn thread_exception_destination(name u32) i32 {
	if system_data != unsafe { nil } {
		if name == system_data.task_self { return 4 }
		port := mach_receive_find(name)
		if port != unsafe { nil } {
			return if port.receive && port.refs != 0 { i32(46) } else { i32(0x10000003) }
		}
		if mach_host_live(name) || mach_semaphore_find(name) != unsafe { nil }
			|| mach_memory_find(name) != unsafe { nil } { return 4 }
		$if linux {
			mach_threads_refresh()
			worker := mach_thread_find(name)
			if worker != unsafe { nil } && !worker.dead { return 0 }
		}
	}
	$if macos { return 0 }
	return i32(0x10000003)
}

fn darwin_thread_get_exception_ports(name u32, mask u32, masks voidptr, count voidptr, handlers voidptr, behaviors voidptr, flavors voidptr) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.ios_mach_threads_lock()
	result := thread_exception_destination(name)
	mut allocated := false
	$if linux { if result == 0 { allocated = mach_thread_find(name).exception_table } }
	C.ios_mach_threads_unlock()
	if result != 0 { return result }
	$if macos { return C.thread_get_exception_ports(name, mask, masks, count, handlers, behaviors, flavors) }
	$if linux {
		if mask & ~u32(0x3ffe) != 0 { return 4 }
		// Fresh threads have no table. A successful swap, even with a zero
		// mask, creates an empty table whose unset actions form one group.
		// Do not read the incoming count or touch unused arrays.
		words := [mask, u32(allocated && mask != 0), 0]!
		if words[1] != 0 { C.memcpy(masks, unsafe { voidptr(&words[0]) }, 4) }
		C.memcpy(count, unsafe { voidptr(&words[1]) }, 4)
		if words[1] != 0 {
			C.memcpy(handlers, unsafe { voidptr(&words[2]) }, 4)
			C.memcpy(behaviors, unsafe { voidptr(&words[2]) }, 4)
			C.memcpy(flavors, unsafe { voidptr(&words[2]) }, 4)
		}
		return 0
	}
}
