// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftCStringFailure {}
fn (_ &SwiftCStringFailure) msg() string { return 'iOS: unsupported Swift withCString representation' }
fn (_ &SwiftCStringFailure) code() int { return 1 }
__global swift_cstring_failure_value = SwiftCStringFailure{}
fn swift_cstring_failure() IError { return unsafe { &swift_cstring_failure_value } }

// Borrow the String and copy exactly its UTF-8 extent into the existing owned
// array representation, including a trailing NUL. A separate buffer keeps the
// bytes stable through nested callbacks and does not require a borrowed large
// literal to have a readable byte beyond its declared length.
fn swift_cstring_buffer_checked(first u64, second u64) !u64 {
	if second & (u64(1) << 61) != 0 {
		if second & (u64(1) << 63) == 0 || second & (u64(1) << 60) != 0 {
			return swift_cstring_failure()
		}
	} else if second & (u64(1) << 60) != 0 || first & (u64(1) << 60) == 0
		|| second & swift_address_mask == 0 { return swift_cstring_failure() }
	return swift_string_utf8(first, second)
}
fn swift_cstring_buffer(first u64, second u64) u64 {
	return swift_cstring_buffer_checked(first, second) or { panic(err) }
}

fn swift_cstring_entry() u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_cstring_arena != 0 { return ios_runtime.swift_cstring_arena }
	$if !arm64 { panic('iOS: Swift withCString requires ARM64') }
	page := usize(C.getpagesize())
	arena := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == unsafe { voidptr(-1) } { panic('iOS: cannot allocate Swift CString entry') }
	base := u64(arena)
	// Measured Swift ABI: closure/context x0/x1, borrowed String x2/x3,
	// result metadata x4, caller's indirect result x8. The closure receives
	// bytes in x0, its context in x20 and the original result pointer in x8.
	// Release the temporary after the callback, including a thrown error in
	// x21; preserve both callback result registers and the caller's x20.
	for i, op in [u32(0xa9bb7bfd), 0xa90153f3, 0xa9025ff6, 0xa90367f8,
		0xf90023e8, 0xaa0003f3, 0xaa0103f6, 0xaa0403f7, 0xaa0203e0, 0xaa0303e1,
		0x580002d0, 0xd63f0200, 0xaa0003f8, 0x91008300, 0xf94023e8, 0xaa1603f4,
		0xaa1703e4, 0xd63f0260, 0xaa0003f6, 0xaa0103f7, 0xaa1503f9, 0xaa1803e0,
		0x58000190, 0xd63f0200, 0xaa1903f5, 0xaa1603e0, 0xaa1703e1, 0xa94153f3,
		0xa9425ff6, 0xa94367f8, 0xa8c57bfd, 0xd65f03c0]! { write32(base + u64(i * 4), op) }
	unsafe {
		*(&u64(base + 128)) = u64(voidptr(swift_cstring_buffer))
		*(&u64(base + 136)) = u64(voidptr(swift_release))
	}
	C.__builtin___clear_cache(arena, unsafe { voidptr(base + 144) })
	if C.mprotect(arena, page, C.PROT_READ | C.PROT_EXEC) != 0 {
		C.munmap(arena, page)
		panic('iOS: cannot seal Swift CString entry')
	}
	ios_runtime.swift_cstring_arena = base
	return base
}
fn swift_cstring_stop() {
	if ios_runtime.swift_cstring_arena == 0 { return }
	if C.munmap(unsafe { voidptr(ios_runtime.swift_cstring_arena) }, usize(C.getpagesize())) != 0 {
		panic('iOS: cannot retire Swift CString entry')
	}
	ios_runtime.swift_cstring_arena = 0
}
