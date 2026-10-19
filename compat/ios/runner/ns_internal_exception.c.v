// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The exported address holds an NSString pointer, as on Foundation and its
// CoreFoundation reexport. It does not provide exception throwing/unwinding.
fn ns_internal_exception_symbol(symbol string) ?u64 {
	if symbol != '_NSInternalInconsistencyException' { return none }
	return ns_exception_name_cell(0)
}

fn ns_exception_name_cell(index int) ?u64 {
	if index < 0 || index > 1 || ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.ns_internal_exception_arena == 0 {
		if ios_runtime.swift_concurrency_retired { return none }
		page := usize(C.getpagesize())
		arena := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if arena == voidptr(-1) { panic('iOS: cannot allocate exception names') }
		base := u64(arena)
		// Preserve the original cell, CFSTR and bytes at offsets 0, 32 and 64.
		objects := [u64(32), 128]!
		bytes := [u64(64), 160]!
		for i, text in ['NSInternalInconsistencyException', 'NSInvalidArgumentException']! {
			object := base + objects[i]
			data := base + bytes[i]
			unsafe {
				*(&u64(base + u64(i * 8))) = object
				*(&u64(object)) = ios_runtime.names['NSString']
				*(&u64(object + 8)) = 0x7c8
				*(&u64(object + 16)) = data
				*(&u64(object + 24)) = u64(text.len)
				C.memcpy(voidptr(data), text.str, usize(text.len))
			}
			ios_runtime.constants[object] = true
		}
		if C.mprotect(arena, page, C.PROT_READ) != 0 { panic('iOS: cannot seal exception names') }
		ios_runtime.ns_internal_exception_arena = base
	}
	return ios_runtime.ns_internal_exception_arena + u64(index * 8)
}

// NSError domains, pools and Swift teardown callbacks may still borrow these
// strings. Retire them only after those owners have drained at image shutdown.
fn ns_internal_exception_stop() {
	arena := ios_runtime.ns_internal_exception_arena
	if arena == 0 { return }
	for i in 0 .. 2 { ios_runtime.constants.delete(read64(arena + u64(i * 8))) }
	if C.munmap(unsafe { voidptr(arena) }, usize(C.getpagesize())) != 0 { panic('iOS: cannot retire exception names') }
	ios_runtime.ns_internal_exception_arena = 0
}
