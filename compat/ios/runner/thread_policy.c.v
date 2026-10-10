// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	fn C.thread_policy_set(u32, i32, &i32, u32) i32
}

fn darwin_thread_policy_set(name u32, flavor i32, policy &i32, count u32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	$if macos { return C.thread_policy_set(name, flavor, policy, count) }
	// The native MIG request holds at most sixteen integer_t words. Its
	// client rejects larger arrays before sending, even to an invalid port.
	if count > 16 { return -307 } // MIG_ARRAY_TOO_LARGE
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	if system_data == unsafe { nil } { return 0x10000003 }
	if name == system_data.task_self { return 4 }
	semaphore := mach_semaphore_find(name)
	if semaphore != unsafe { nil } && !semaphore.terminated { return 4 }
	mach_threads_refresh()
	port := mach_thread_find(name)
	if port == unsafe { nil } || port.dead || !port.started {
		return 0x10000003 // MACH_SEND_INVALID_DEST
	}
	match flavor {
		1 {
			// Zero words selects THREAD_STANDARD_POLICY. Extended policy uses
			// its first word to request fair timesharing; fixed-priority mode
			// cannot be mapped to a fictitious successful native request.
			if count != 0 {
				if policy == unsafe { nil } { return 4 }
				if unsafe { *policy } != 1 { return 46 }
			}
			// A remote native pthread may exit during a Mach-port operation.
			// Only the caller's live handle is safe for libc scheduling; no
			// borrowed pthread pointer is dereferenced after another thread exits.
			if port.handle != u64(C.pthread_self()) { return 46 }
			result := C.ios_thread_setsched(port.handle, 0, 0, 0)
			return if result == 0 { i32(0) } else if result == C.EPERM || result == C.EACCES {
				i32(8) // KERN_NO_ACCESS
			} else { i32(5) } // KERN_FAILURE
		}
		2 {
			if count < 4 { return 4 }
			return 46 // Time-constraint scheduling needs a native deadline backend.
		}
		3 {
			if count < 1 { return 4 }
			return 46 // Mach importance is not a Linux process-wide nice value.
		}
		4 {
			// Darwin on this ARM64 Mac rejects cache-affinity hints, including
			// empty arrays. Binding a thread to one CPU has different semantics.
			return 46 // KERN_NOT_SUPPORTED
		}
		else { return 4 }
	}
}

fn thread_policy_symbol(symbol string) ?u64 {
	return if symbol == '_thread_policy_set' {
		u64(unsafe { voidptr(darwin_thread_policy_set) })
	} else { none }
}
