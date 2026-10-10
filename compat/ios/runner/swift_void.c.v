// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The empty tuple has no value bytes. Its witnesses return the destination
// without inspecting either address, even when a caller supplies no storage.
fn swift_void_copy(destination u64, source u64, metadata u64) u64 { return destination }
fn swift_void_destroy(value u64, metadata u64) {}

// Include the payload case when choosing the tag width. The installed runtime
// performs this addition in UInt32: UINT32_MAX wraps to zero tag bytes.
fn swift_void_tag_bytes(empty_cases u32) u32 {
	if empty_cases == 0 || empty_cases == 0xffffffff { return 0 }
	return if empty_cases < 255 { u32(1) } else if empty_cases < 65535 { u32(2) } else { u32(4) }
}
fn swift_void_enum_get(value u64, empty_cases u32, metadata u64) u32 {
	mut tag := u32(0)
	for i in u32(0) .. swift_void_tag_bytes(empty_cases) {
		tag |= u32(unsafe { *(&u8(value + u64(i))) }) << (i * 8)
	}
	return tag
}
fn swift_void_enum_store(value u64, which_case u32, empty_cases u32, metadata u64) {
	for i in u32(0) .. swift_void_tag_bytes(empty_cases) {
		unsafe { *(&u8(value + u64(i))) = u8(which_case >> (i * 8)) }
	}
}

fn swift_void_full_metadata() u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_void_arena != 0 { return ios_runtime.swift_void_arena }
	page := usize(C.getpagesize())
	arena := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == unsafe { voidptr(-1) } { panic('iOS: cannot allocate Swift Void metadata') }
	full := u64(arena)
	witness := full + 32
	unsafe {
		*(&u64(full)) = witness
		*(&u64(full + 8)) = 0x301 // Tuple metadata; zero elements and null labels follow.
	}
	for i, function in [u64(unsafe { voidptr(swift_void_copy) }),
		u64(unsafe { voidptr(swift_void_destroy) }), u64(unsafe { voidptr(swift_void_copy) }),
		u64(unsafe { voidptr(swift_void_copy) }), u64(unsafe { voidptr(swift_void_copy) }),
		u64(unsafe { voidptr(swift_void_copy) }), u64(unsafe { voidptr(swift_void_enum_get) }),
		u64(unsafe { voidptr(swift_void_enum_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = function }
	}
	// Size zero, stride one, alignment one, POD, inline, bitwise-takable,
	// no extra inhabitants. Anonymous memory supplies the remaining zeros.
	unsafe { *(&u64(witness + 72)) = 1 }
	if C.mprotect(arena, page, C.PROT_READ) != 0 {
		C.munmap(arena, page)
		panic('iOS: cannot seal Swift Void metadata')
	}
	ios_runtime.swift_void_arena = full
	return full
}
fn swift_void_stop() {
	if ios_runtime.swift_void_arena == 0 { return }
	if C.munmap(unsafe { voidptr(ios_runtime.swift_void_arena) }, usize(C.getpagesize())) != 0 {
		panic('iOS: cannot retire Swift Void metadata')
	}
	ios_runtime.swift_void_arena = 0
}
