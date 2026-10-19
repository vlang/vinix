// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Objective-C EH typeinfo is a C++ ABI record, not an NSString pointer cell.
// This supplies metadata and matching only; Mach-O exception unwinding is not implemented.
fn ns_exception_type_symbol(symbol string) ?u64 {
	if symbol != '_OBJC_EHTYPE_$_NSException' || ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.ns_exception_type_arena == 0 {
		if ios_runtime.swift_concurrency_retired { return none }
		page := usize(C.getpagesize())
		arena := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if arena == voidptr(-1) { panic('iOS: cannot allocate exception typeinfo') }
		base := u64(arena)
		noop := u64(unsafe { voidptr(ns_exception_type_noop) })
		no := u64(unsafe { voidptr(ns_exception_type_false) })
		stop := u64(unsafe { voidptr(ns_exception_type_unsupported) })
		table := [u64(0), base + 32, noop, noop, no, no,
			u64(unsafe { voidptr(ns_exception_type_catch) }), no, no, stop, stop, stop, stop]!
		unsafe {
			// Record: vptr, type name, unremapped Class. The internal id record
			// is also the vtable's typeinfo prefix, as in the native ABI.
			*(&u64(base)) = base + 80
			*(&u64(base + 8)) = base + 192
			*(&u64(base + 16)) = ios_runtime.names['NSException']
			*(&u64(base + 32)) = base + 80
			*(&u64(base + 40)) = base + 208
			C.memcpy(voidptr(base + 64), &table[0], usize(104))
			C.memcpy(voidptr(base + 192), c'NSException', usize(12))
			C.memcpy(voidptr(base + 208), c'id', usize(3))
		}
		if C.mprotect(arena, page, C.PROT_READ) != 0 { panic('iOS: cannot seal exception typeinfo') }
		ios_runtime.ns_exception_type_arena = base
	}
	return ios_runtime.ns_exception_type_arena
}

fn ns_exception_type_noop() {}
fn ns_exception_type_false() bool { return false }
fn ns_exception_type_unsupported() { panic('iOS: unsupported exception typeinfo virtual operation') }

fn ns_exception_type_catch(caught u64, thrown u64, object &u64, outer u32) bool {
	if ios_runtime == unsafe { nil } { return false }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	arena := ios_runtime.ns_exception_type_arena
	if arena == 0 || read64(thrown) != arena + 80 { return false }
	// Native matching adjusts even a nonmatching Objective-C exception, but
	// leaves a foreign exception pointer untouched.
	unsafe { *object = read64(*object) }
	if caught == arena + 32 { return true }
	return objc_is_kind(unsafe { *object }, read64(caught + 16))
}

// Pool and Swift destruction may still inspect typeinfo and its Class. Retire
// the page after callbacks drain and before class descriptors are freed.
fn ns_exception_type_stop() {
	arena := ios_runtime.ns_exception_type_arena
	if arena == 0 { return }
	if C.munmap(unsafe { voidptr(arena) }, usize(C.getpagesize())) != 0 { panic('iOS: cannot retire exception typeinfo') }
	ios_runtime.ns_exception_type_arena = 0
}
