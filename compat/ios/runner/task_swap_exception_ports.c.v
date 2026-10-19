// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos { fn C.task_swap_exception_ports(u32, u32, u32, i32, i32, voidptr, voidptr, voidptr, voidptr, voidptr) i32 }

// Caller holds the namespace lock. COPY_SEND also accepts null/dead names.
fn task_swap_right(name u32) MachExceptionRight {
	if system_data != unsafe { nil } { return mach_exception_right(name) }
	if name == 0 || name == 0xffffffff { return .dead }
	$if macos {
		mut kind := u32(0)
		if C.ios_native_port_type(name, unsafe { &kind }) != 0 { return .missing }
		if kind & 0x100000 != 0 { return .dead }
		if kind & 0x10000 != 0 { return .send }
	}
	return .missing
}

fn task_swap_arguments(mask u32, nullable bool, kernel_handler bool, behavior i32, flavor i32) i32 {
	if mask & ~u32(0x3ffe) != 0 { return 4 }
	base := u32(behavior) & 0x1fffffff
	if base == 4 && u32(behavior) & 0x80000000 == 0 { return 4 }
	if !nullable && base !in [u32(1),2,3,4,5]! { return 4 }
	// Kernel-object ports cannot be exception handlers, even with a zero
	// mask. Native checks this after mask/behavior, before thread flavor.
	if kernel_handler { return 17 }
	// ARM64 thread-state flavors accepted by the measured native API. These
	// identify an exception record; a zero mask does not access thread state.
	if flavor !in [i32(0),1,2,3,4,5,6,7,9,10,14,15,16,17,25,27]! { return 4 }
	return 0
}

fn darwin_task_swap_exception_ports(task u32, mask u32, new_port u32, behavior i32, flavor i32, masks voidptr, count voidptr, handlers voidptr, behaviors voidptr, flavors voidptr) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.ios_mach_threads_lock()
	if system_data != unsafe { nil } { mach_threads_refresh() }
	mut result := task_exception_destination(task)
	$if macos { if result == 0 && task_swap_right(task) != .send { result = 0x10000003 } }
	if result == i32(0x10000003) { C.ios_mach_threads_unlock(); return result }
	right := task_swap_right(new_port)
	// Transport resolves the destination first, then COPY_SEND descriptors,
	// before the receiving kernel object checks its kind or scalar arguments.
	if right == .missing { C.ios_mach_threads_unlock(); return 0x1000000a }
	mut destination := task; mut replacement := new_port; mut compatibility := false
	kernel_handler := right == .send && !mach_receive_known(new_port)
	$if macos {
		if system_data != unsafe { nil } {
			if task == system_data.task_self { destination = C.mach_task_self() }
			if new_port == system_data.task_self { replacement = C.mach_task_self() }
			else { compatibility = mach_receive_known(new_port) || mach_semaphore_known(new_port) || mach_memory_known(new_port) || mach_host_known(new_port) }
		}
		if right == .dead && new_port != 0 { replacement = 0xffffffff; compatibility = false }
	}
	C.ios_mach_threads_unlock()
	if result != 0 { return result }
	$if macos {
		if !compatibility { return C.task_swap_exception_ports(destination, mask, replacement, behavior, flavor, masks, count, handlers, behaviors, flavors) }
	}
	validation := task_swap_arguments(mask, right == .dead, kernel_handler, behavior, flavor)
	if validation != 0 { return validation }
	// A zero mask changes no actions and transfers no returned references.
	// Other successful Vinix swaps may only clear an already-unset action to
	// exactly null/zero. No handler or exception-policy state is fabricated.
	if mask != 0 {
		$if macos { return 46 }
		if new_port != 0 || behavior != 0 || flavor != 0 { return 46 }
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
