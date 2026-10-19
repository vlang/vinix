// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	fn C.task_threads(u32, voidptr, voidptr) i32
	fn C.mach_vm_deallocate(u32, u64, u64) i32
}

fn darwin_task_threads(task u32, output voidptr, count voidptr) i32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.ios_mach_threads_lock()
	if system_data == unsafe { nil } { C.ios_mach_threads_unlock(); return i32(0x10000003) }
	result := task_exception_destination(task)
	mut destination := task
	$if macos { if task == system_data.task_self { destination = C.mach_task_self() } }
	if result != 0 { C.ios_mach_threads_unlock(); return result }
	mut address := u64(0)
	mut length := u32(0)
	$if macos {
		C.ios_mach_threads_unlock()
		mut native := u64(0)
		status := C.task_threads(destination, unsafe { &native }, unsafe { &length })
		if status != 0 { return status }
		// Retain the native COPY_SEND rights, but move the OOL storage into
		// our VM registry so the app's vm_deallocate can release it normally.
		C.ios_mach_threads_lock()
		if length != 0 {
			size := u64(length) * 4
			rounded := mach_size(size) or { panic('iOS: oversized native thread list') }
			address = mach_allocate(rounded, 0, true) or {
				C.ios_mach_threads_unlock()
				for i in 0 .. length { C.ios_native_port_deallocate(read32(native + u64(i) * 4)) }
				C.mach_vm_deallocate(C.mach_task_self(), native, size)
				return 3
			}
			C.memcpy(voidptr(address), voidptr(native), usize(size))
		}
		C.ios_mach_threads_unlock()
		if length != 0 { C.mach_vm_deallocate(C.mach_task_self(), native, u64(length) * 4) }
	} $else {
		// The namespace covers entry/callback threads, Darwin pthreads,
		// NSThreads and the runner's dispatch/network workers. Native foreign
		// pthreads that never enter the adapter are outside this namespace.
		mach_threads_refresh()
		if mach_thread_current() == 0 { C.ios_mach_threads_unlock(); return 6 }
		mut port := system_data.thread_ports
		for port != unsafe { nil } { if !port.dead { length++ }; port = port.next }
		rounded := mach_size(u64(length) * 4) or { panic('iOS: oversized thread namespace') }
		address = mach_allocate(rounded, 0, true) or { C.ios_mach_threads_unlock(); return 3 }
		mut index := u64(0)
		port = system_data.thread_ports
		for port != unsafe { nil } {
			if !port.dead {
				// Enumeration can recreate a send right whose urefs were zero.
				// Saturated Mach send references stay pinned at their limit.
				if port.refs != 65535 { port.refs++ }
				write32(address + index * 4, port.name)
				index++
			}
			port = port.next
		}
		C.ios_mach_threads_unlock()
	}
	// Output-only count. Native MIG copies the pointer before the 32-bit
	// count, including when the caller supplies unaligned or overlapping spans.
	C.memcpy(output, unsafe { voidptr(&address) }, 8)
	C.memcpy(count, unsafe { voidptr(&length) }, 4)
	return 0
}
