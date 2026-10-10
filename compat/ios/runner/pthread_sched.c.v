// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.ios_thread_getsched(u64, &i32) i32
fn C.ios_thread_setsched(u64, i32, i32, i32) i32
fn C.sched_yield() i32

fn darwin_pthread_getschedparam(handle u64, policy &i32, parameters u64) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if handle == 0 { return 3 }
	mut fields := [i32(0), i32(0), i32(0)]!
	result := C.ios_thread_getsched(handle, unsafe { &fields[0] })
	if result != 0 { return i32(darwin_native_error(int(result))) }
	$if linux {
		match fields[0] {
			0 {
				if fields[1] != 0 { return 45 }
				fields[0] = 1
				fields[1] = 31 // Darwin's default ordinary priority maps to native zero.
			}
			1 { fields[0] = 4 }
			2 {}
			else { return 45 }
		}
		// Darwin copies this opaque word from its inline scheduling state. Only
		// its measured default is supported on Vinix; setters reject alternatives.
		fields[2] = 10
	}
	if policy != unsafe { nil } { unsafe { *policy = fields[0] } }
	if parameters != 0 {
		write32(parameters, u32(fields[1]))
		write32(parameters + 4, u32(fields[2]))
	}
	return 0
}

fn darwin_pthread_setschedparam(handle u64, policy i32, parameters u64) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if handle == 0 { return 3 }
	if parameters == 0 || (policy != 1 && policy != 2 && policy != 4) { return 22 }
	mut priority := i32(read32(parameters))
	opaque := i32(read32(parameters + 4))
	if priority < 0 { return 22 }
	mut native_policy := policy
	$if linux {
		if opaque != 10 { return 45 }
		if policy == 1 {
			// Other ordinary priorities need a native per-thread weighting adapter;
			// do not apply a process-wide nice change or remember a fictitious value.
			if priority != 31 { return 45 }
			native_policy = 0
			priority = 0
		} else {
			if priority < 1 || priority > 99 { return 45 }
			native_policy = if policy == 4 { i32(1) } else { i32(2) }
		}
	}
	return i32(darwin_native_error(int(C.ios_thread_setsched(handle, native_policy, priority, opaque))))
}

fn darwin_sched_priority_min(_policy i32) i32 {
	// The installed Mac implementation ignores the policy, even invalid ones.
	return 15
}

fn darwin_sched_priority_max(_policy i32) i32 { return 47 }

fn darwin_sched_yield() i32 {
	previous := unsafe { *C.ios_errno_address() }
	result := C.sched_yield()
	if result == 0 { darwin_set_errno(previous) }
	else { darwin_set_errno(i32(darwin_native_error(int(unsafe { *C.ios_errno_address() })))) }
	return result
}

fn pthread_sched_symbol(symbol string) ?u64 {
	return match symbol {
		'_pthread_getschedparam' { u64(unsafe { voidptr(darwin_pthread_getschedparam) }) }
		'_pthread_setschedparam' { u64(unsafe { voidptr(darwin_pthread_setschedparam) }) }
		'_sched_get_priority_min' { u64(unsafe { voidptr(darwin_sched_priority_min) }) }
		'_sched_get_priority_max' { u64(unsafe { voidptr(darwin_sched_priority_max) }) }
		'_sched_yield' { u64(unsafe { voidptr(darwin_sched_yield) }) }
		else { return none }
	}
}
