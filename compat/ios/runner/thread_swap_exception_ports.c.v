// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos { fn C.thread_swap_exception_ports(u32, u32, u32, i32, i32, voidptr, voidptr, voidptr, voidptr, voidptr) i32 }

fn darwin_thread_swap_exception_ports(name u32, mask u32, new_port u32, behavior i32, flavor i32, masks voidptr, count voidptr, handlers voidptr, behaviors voidptr, flavors voidptr) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.ios_mach_threads_lock()
	if system_data != unsafe { nil } { mach_threads_refresh() }
	result := thread_exception_destination(name)
	if result == i32(0x10000003) { C.ios_mach_threads_unlock(); return result }
	$if macos {
		if result == 0 && task_swap_right(name) != .send { C.ios_mach_threads_unlock(); return 0x10000003 }
	}
	right := task_swap_right(new_port)
	// MIG resolves the destination and COPY_SEND descriptor before scalar
	// validation, including when the destination names a different object kind.
	if right == .missing { C.ios_mach_threads_unlock(); return 0x1000000a }
	if result != 0 { C.ios_mach_threads_unlock(); return result }
	mut replacement := new_port
	mut compatibility := false
	$if macos {
		if system_data != unsafe { nil } {
			if new_port == system_data.task_self { replacement = C.mach_task_self() }
			else { compatibility = mach_receive_known(new_port) || mach_semaphore_known(new_port) || mach_memory_known(new_port) || mach_host_known(new_port) }
		}
		if right == .dead && new_port != 0 { replacement = 0xffffffff; compatibility = false }
		if !compatibility {
			C.ios_mach_threads_unlock()
			return C.thread_swap_exception_ports(name, mask, replacement, behavior, flavor, masks, count, handlers, behaviors, flavors)
		}
	}
	validation := task_swap_arguments(mask, right == .dead, right == .send && !mach_receive_known(new_port), behavior, flavor)
	if validation != 0 { C.ios_mach_threads_unlock(); return validation }
	if mask != 0 {
		$if macos { C.ios_mach_threads_unlock(); return 46 }
		if new_port != 0 || behavior != 0 || flavor != 0 { C.ios_mach_threads_unlock(); return 46 }
	}
	$if linux {
		// Native swaps allocate an empty action table even with a zero mask.
		// Track that observable state on the existing thread record. Only exact
		// null/zero clears are supported; no handler or policy is manufactured.
		mut worker := mach_thread_find(name)
		worker.exception_table = true
	}
	C.ios_mach_threads_unlock()
	$if macos {
		// A compatibility handler cannot be passed as a native port. A zero
		// mask uses no handler, but must still create the native empty table.
		return C.thread_swap_exception_ports(name, mask, 0, behavior, flavor, masks, count, handlers, behaviors, flavors)
	}
	words := [mask, u32(mask != 0), 0]!
	if mask != 0 { C.memcpy(masks, unsafe { voidptr(&words[0]) }, 4) }
	C.memcpy(count, unsafe { voidptr(&words[1]) }, 4)
	if mask != 0 {
		C.memcpy(handlers, unsafe { voidptr(&words[2]) }, 4)
		C.memcpy(behaviors, unsafe { voidptr(&words[2]) }, 4)
		C.memcpy(flavors, unsafe { voidptr(&words[2]) }, 4)
	}
	return 0
}
