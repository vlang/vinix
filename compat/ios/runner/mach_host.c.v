// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <mach/mach.h>
	fn C.mach_host_self() u32
	fn C.host_statistics(u32, i32, voidptr, &u32) i32
	fn C.host_statistics64(u32, i32, voidptr, &u32) i32
}

// Separate from task (1), thread (low byte 3) and semaphore (low byte 7)
// names. Retired names never refer to a later image's host send right.
__global mach_host_next_name = u64(0x7000010b)

fn mach_host_known(name u32) bool {
	return name >= 0x7000010b && u64(name) < C.ios_load_pointer(unsafe { &mach_host_next_name }) && name & 0xff == 11
}

// Caller holds the shared namespace lock.
fn mach_host_live(name u32) bool {
	return system_data != unsafe { nil } && name == system_data.host_name && system_data.host_refs != 0
}

fn darwin_mach_host_self() u32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	$if macos { return C.mach_host_self() }
	if system_data == unsafe { nil } { return 0 }
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	if system_data.host_refs == 0 {
		next := C.ios_load_pointer(unsafe { &mach_host_next_name })
		if next >= 0xffffffff { return 0 }
		system_data.host_name = u32(next)
		C.ios_store_pointer(unsafe { &mach_host_next_name }, next + 0x100)
	}
	if system_data.host_refs != 65535 { system_data.host_refs++ }
	return system_data.host_name
}

fn mach_host_port_type(name u32, output &u32) ?i32 {
	if !mach_host_known(name) { return none }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	if !mach_host_live(name) { return i32(15) }
	unsafe { *output = 0x10000 }
	return i32(0)
}

fn mach_host_port_refs(name u32, right i32, output &u32) ?i32 {
	if !mach_host_known(name) { return none }
	if right < 0 || right > 5 { return i32(18) }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	if !mach_host_live(name) { return i32(15) }
	unsafe { *output = if right == 0 { system_data.host_refs } else { u32(0) } }
	return i32(0)
}

fn mach_host_port_mod_refs(name u32, right i32, delta i32) ?i32 {
	if !mach_host_known(name) { return none }
	if right < 0 || right > 5 { return i32(18) }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	if !mach_host_live(name) { return i32(15) }
	if right != 0 { return i32(17) }
	if delta < -65535 || delta > 65535 { return i32(18) }
	if system_data.host_refs == 65535 { return if delta == -65535 { i32(20) } else { i32(0) } }
	refs := i64(system_data.host_refs) + i64(delta)
	if refs < 0 { return i32(18) }
	system_data.host_refs = u32(if refs > 65535 { i64(65535) } else { refs })
	return i32(0)
}

// Validate the destination before flavor/count/output, like the native MIG
// client. Other live kernel objects reject it with KERN_INVALID_HOST (22).
fn mach_host_destination(name u32) i32 {
	if system_data == unsafe { nil } { return i32(0x10000003) }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	if mach_host_live(name) { return 0 }
	port_right := mach_receive_find(name)
	if port_right != unsafe { nil } { return if port_right.receive && port_right.refs != 0 { i32(46) } else { i32(0x10000003) } }
	if name == system_data.task_self || mach_semaphore_find(name) != unsafe { nil } || mach_memory_find(name) != unsafe { nil } { return 22 }
	$if linux {
		mach_threads_refresh()
		port := mach_thread_find(name)
		if port != unsafe { nil } && !port.dead { return 22 }
	}
	return i32(0x10000003)
}

fn mach_host_statistics(host u32, flavor i32, output voidptr, count &u32, wide bool) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	$if macos {
		if system_data != unsafe { nil } && (host == system_data.task_self || mach_semaphore_known(host) || mach_host_known(host) || mach_memory_known(host) || mach_receive_known(host)) {
			return mach_host_destination(host)
		}
		return if wide { C.host_statistics64(host, flavor, output, count) } else { C.host_statistics(host, flavor, output, count) }
	}
	destination := mach_host_destination(host)
	if destination != 0 { return destination }
	if flavor != 2 && !(wide && flavor == 4) { return 4 }
	mut requested := u32(0)
	unsafe { C.memcpy(voidptr(&requested), voidptr(count), 4) }
	length := mach_host_statistics_count(requested, flavor == 4)
	if length == 0 { return 5 }
	mut snapshot := MachHostMemory{}
	if !mach_host_memory_read(unsafe { &snapshot }) { return 5 }
	mach_host_statistics_copy(snapshot, flavor == 4, length, output, count)
	return 0
}

fn darwin_host_statistics(host u32, flavor i32, output voidptr, count &u32) i32 {
	return mach_host_statistics(host, flavor, output, count, false)
}

fn darwin_host_statistics64(host u32, flavor i32, output voidptr, count &u32) i32 {
	return mach_host_statistics(host, flavor, output, count, true)
}

fn mach_host_symbol(symbol string) ?u64 {
	return match symbol {
		'_mach_host_self' { u64(unsafe { voidptr(darwin_mach_host_self) }) }
		'_host_statistics' { u64(unsafe { voidptr(darwin_host_statistics) }) }
		'_host_statistics64' { u64(unsafe { voidptr(darwin_host_statistics64) }) }
		else { return none }
	}
}
