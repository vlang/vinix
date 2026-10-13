// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Builtin.UnknownObject is an ordinary object reference, with neither the
// BridgeObject encoding nor NativeObject's unconditional native ARC. Like the
// installed witnesses, assignments publish before retiring the previous owner
// so that a reentrant destructor sees the replacement. Moved/destroyed storage
// is uninitialized; these witnesses leave its bytes unchanged.
fn swift_unknown_value_copy(destination u64, source u64, _metadata u64) u64 {
	owner := swift_unknown_retain(read64(source))
	unsafe { *(&u64(destination)) = owner }
	return destination
}
fn swift_unknown_value_destroy(value u64, _metadata u64) {
	swift_unknown_release(read64(value))
}
fn swift_unknown_value_assign_copy(destination u64, source u64, _metadata u64) u64 {
	previous := read64(destination)
	owner := swift_unknown_retain(read64(source))
	unsafe { *(&u64(destination)) = owner }
	swift_unknown_release(previous)
	return destination
}
fn swift_unknown_value_take(destination u64, source u64, _metadata u64) u64 {
	unsafe { *(&u64(destination)) = read64(source) }
	return destination
}
fn swift_unknown_value_assign_take(destination u64, source u64, _metadata u64) u64 {
	previous := read64(destination)
	unsafe { *(&u64(destination)) = read64(source) }
	swift_unknown_release(previous)
	return destination
}
fn swift_unknown_value_enum_get(value u64, empty_cases u32, _metadata u64) u32 {
	mut owner := u64(0)
	C.memcpy(unsafe { &owner }, unsafe { voidptr(value) }, 8)
	if empty_cases > 0x7fffffff && unsafe { *(&u8(value + 8)) } != 0 {
		return u32(owner) + 0x80000000
	}
	return if owner >> 32 == 0 { u32(owner) + 1 } else { u32(0) }
}
fn swift_unknown_value_enum_store(value u64, which_case u32, empty_cases u32, _metadata u64) {
	if empty_cases > 0x7fffffff {
		unsafe { *(&u8(value + 8)) = if which_case > 0x7fffffff { u8(1) } else { u8(0) } }
	}
	if which_case != 0 {
		owner := if which_case <= 0x7fffffff { u64(which_case - 1) } else { u64(which_case - 0x80000000) }
		C.memcpy(unsafe { voidptr(value) }, unsafe { &owner }, 8)
	}
}

fn swift_unknown_value_witnesses() u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_unknown_value_arena != 0 { return ios_runtime.swift_unknown_value_arena }
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { panic('iOS: cannot allocate Swift UnknownObject witnesses') }
	table := u64(allocation)
	for i, target in [u64(unsafe { voidptr(swift_unknown_value_copy) }),
		u64(unsafe { voidptr(swift_unknown_value_destroy) }), u64(unsafe { voidptr(swift_unknown_value_copy) }),
		u64(unsafe { voidptr(swift_unknown_value_assign_copy) }), u64(unsafe { voidptr(swift_unknown_value_take) }),
		u64(unsafe { voidptr(swift_unknown_value_assign_take) }), u64(unsafe { voidptr(swift_unknown_value_enum_get) }),
		u64(unsafe { voidptr(swift_unknown_value_enum_store) })]! {
		unsafe { *(&u64(table + u64(i * 8))) = target }
	}
	unsafe { *(&u64(table + 64)) = 8; *(&u64(table + 72)) = 8 }
	write32(table + 80, 0x10007) // Non-POD, inline, bitwise-takable, alignment eight.
	write32(table + 84, 0x7fffffff)
	// The measured single-reference enum encoding matches Array and ObjC
	// wrappers. memcpy also permits unaligned, exactly bounded enum storage.
	if C.mprotect(allocation, page, C.PROT_READ) != 0 {
		C.munmap(allocation, page)
		panic('iOS: cannot seal Swift UnknownObject witnesses')
	}
	ios_runtime.swift_unknown_value_arena = table
	return table
}
fn swift_unknown_value_stop() {
	if ios_runtime.swift_unknown_value_arena == 0 { return }
	if C.munmap(unsafe { voidptr(ios_runtime.swift_unknown_value_arena) }, usize(C.getpagesize())) != 0 {
		panic('iOS: cannot retire Swift UnknownObject witnesses')
	}
	ios_runtime.swift_unknown_value_arena = 0
}
