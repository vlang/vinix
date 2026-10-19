// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <mach/exc.h>
	fn C.exception_raise(u32, u32, u32, i32, &i32, u32) i32
	fn C.exception_raise_state(u32, i32, &i32, u32, &i32, &u32, u32, &u32, &u32) i32
	fn C.exception_raise_state_identity(u32, u32, u32, i32, &i32, u32, &i32, &u32, u32, &u32, &u32) i32
}

enum MachExceptionRight {
	missing
	dead
	send
}

// Caller holds the shared task namespace lock. COPY_SEND accepts null and dead
// descriptors, but an unallocated name is MACH_SEND_INVALID_RIGHT. Destination
// lookup happens first, and only a live send right can be a destination.
fn mach_exception_right(name u32) MachExceptionRight {
	if name == 0 || name == 0xffffffff { return .dead }
	if name == system_data.task_self { return .send }
	if mach_receive_known(name) {
		port := mach_receive_find(name)
		if port == unsafe { nil } { return .missing }
		if !port.receive { return .dead }
		return if port.refs != 0 { MachExceptionRight.send } else { MachExceptionRight.missing }
	}
	if mach_host_known(name) { return if mach_host_live(name) { MachExceptionRight.send } else { MachExceptionRight.missing } }
	if mach_memory_known(name) { return if mach_memory_find(name) != unsafe { nil } { MachExceptionRight.send } else { MachExceptionRight.missing } }
	if mach_semaphore_known(name) {
		semaphore := mach_semaphore_find(name)
		if semaphore == unsafe { nil } { return .missing }
		// Destroy terminates synchronization, but retained send references
		// still name the kernel semaphore port until the last one is dropped.
		return .send
	}
	$if macos {
		mut kind := u32(0)
		if C.ios_native_port_type(name, unsafe { &kind }) != 0 { return .missing }
		if kind & 0x100000 != 0 { return .dead }
		return if kind & 0x10000 != 0 { MachExceptionRight.send } else { MachExceptionRight.missing }
	}
	port := mach_thread_find(name)
	if port == unsafe { nil } { return .missing }
	return if port.dead { MachExceptionRight.dead } else { MachExceptionRight.send }
}

// Kernel task/thread/semaphore ports reject exception RPCs, as measured on
// Darwin: KERN_FAILURE for raise, KERN_INVALID_ARGUMENT for the state forms.
// This never reports successful delivery or intercepts a kernel fault. On the
// Mac, native ports use the native transport; compatibility semaphores and the
// compatibility task name stay in this namespace. The inline-message transport
// rejects typed exception RPCs to user receive ports until it can transfer rights.
fn mach_exception_kernel_result(destination u32, worker u32, task u32, descriptors bool, state bool) ?i32 {
	if system_data == unsafe { nil } {
		$if macos { return none }
		return i32(0x10000003)
	}
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	$if macos {
		if destination != system_data.task_self && !mach_semaphore_known(destination) && !mach_memory_known(destination) && !mach_receive_known(destination) { return none }
	}
	mach_threads_refresh()
	if mach_exception_right(destination) != .send { return i32(0x10000003) }
	if descriptors && (mach_exception_right(worker) == .missing || mach_exception_right(task) == .missing) {
		return i32(0x1000000a)
	}
	// Public receive ports can exchange inline messages, but typed exception
	// RPCs carry rights/descriptors this transport does not implement yet.
	if mach_receive_known(destination) { return i32(46) }
	return if state { i32(4) } else { i32(5) }
}

fn darwin_exception_raise(destination u32, worker u32, task u32, exception i32, code &i32, code_count u32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if code_count > 2 { return -307 }
	if result := mach_exception_kernel_result(destination, worker, task, true, false) { return result }
	$if macos { return C.exception_raise(destination, worker, task, exception, code, code_count) }
	return i32(0x10000003)
}

fn darwin_exception_raise_state(destination u32, exception i32, code &i32, code_count u32, flavor &i32, old_state &u32, old_count u32, new_state &u32, new_count &u32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if code_count > 2 || old_count > 1296 { return -307 }
	if result := mach_exception_kernel_result(destination, 0, 0, false, true) { return result }
	$if macos { return C.exception_raise_state(destination, exception, code, code_count, flavor, old_state, old_count, new_state, new_count) }
	return i32(0x10000003)
}

fn darwin_exception_raise_state_identity(destination u32, worker u32, task u32, exception i32, code &i32, code_count u32, flavor &i32, old_state &u32, old_count u32, new_state &u32, new_count &u32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if code_count > 2 || old_count > 1296 { return -307 }
	if result := mach_exception_kernel_result(destination, worker, task, true, true) { return result }
	$if macos { return C.exception_raise_state_identity(destination, worker, task, exception, code, code_count, flavor, old_state, old_count, new_state, new_count) }
	return i32(0x10000003)
}

fn mach_exception_symbol(symbol string) ?u64 {
	return match symbol {
		'_task_swap_exception_ports' { u64(unsafe { voidptr(darwin_task_swap_exception_ports) }) }
		'_task_info' { u64(unsafe { voidptr(darwin_task_info) }) }
		'_task_get_exception_ports' { u64(unsafe { voidptr(darwin_task_get_exception_ports) }) }
		'_exception_raise' { u64(unsafe { voidptr(darwin_exception_raise) }) }
		'_exception_raise_state' { u64(unsafe { voidptr(darwin_exception_raise_state) }) }
		'_exception_raise_state_identity' { u64(unsafe { voidptr(darwin_exception_raise_state_identity) }) }
		else { return none }
	}
}
