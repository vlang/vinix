// SPDX-License-Identifier: GPL-2.0-or-later
module main

// ARM64 swift_retain/release use preserve_most, unlike their batch and bridge
// variants. In addition to AAPCS callee saves, x9-x15 must survive the call.
// Emit two immutable thunks in V; the bodies remain ordinary V functions.
// Swift Runtime/Config.h and Clang's preserve_most declaration document this.
fn swift_arc_emit(address u64, target u64) {
	write32(address, 0xa9bb7bfd) // stp x29,x30,[sp,#-80]!
	for i in 0 .. 4 {
		reg := u32(9 + i * 2)
		other := if i == 3 { u32(19) } else { reg + 1 }
		offset := u32(2 + i * 2) // Scaled byte offsets 16,32,48,64.
		write32(address + u64(1 + i) * 4, 0xa9000000 | (offset << 15) | (other << 10) | (31 << 5) | reg)
		write32(address + u64(7 + i) * 4, 0xa9400000 | (offset << 15) | (other << 10) | (31 << 5) | reg)
	}
	write32(address + 20, 0x58000130) // ldr x16,literal at +56
	write32(address + 24, 0xd63f0200) // blr x16
	write32(address + 44, 0xa8c57bfd) // ldp x29,x30,[sp],#80
	write32(address + 48, 0xd65f03c0) // ret
	write32(address + 52, 0xd503201f) // align the literal
	unsafe { *(&u64(address + 56)) = target }
}

fn swift_arc_entry(releasing bool) u64 {
	$if arm64 {
		C.ios_objc_initialize_lock()
		defer { C.ios_objc_initialize_unlock() }
		if ios_runtime.swift_arc_code == 0 {
			page := usize(C.getpagesize())
			code := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
				C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
			if code == unsafe { voidptr(-1) } { panic('iOS: cannot allocate Swift ARC thunks') }
			swift_arc_emit(u64(code), u64(unsafe { voidptr(swift_retain) }))
			swift_arc_emit(u64(code) + 64, u64(unsafe { voidptr(swift_release) }))
			C.__builtin___clear_cache(code, unsafe { voidptr(u64(code) + 128) })
			if C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) != 0 {
				C.munmap(code, page)
				panic('iOS: cannot seal Swift ARC thunks')
			}
			ios_runtime.swift_arc_code = u64(code)
		}
		return ios_runtime.swift_arc_code + if releasing { u64(64) } else { u64(0) }
	} $else {
		return if releasing { u64(unsafe { voidptr(swift_release) }) } else { u64(unsafe { voidptr(swift_retain) }) }
	}
}

fn swift_arc_stop() {
	// Runtime shutdown already joined dispatch workers and drained callbacks.
	// Do not unmap entry points while an app or a worker can still execute them.
	if ios_runtime.swift_arc_code != 0 {
		if C.munmap(unsafe { voidptr(ios_runtime.swift_arc_code) }, usize(C.getpagesize())) != 0 {
			panic('iOS: cannot retire Swift ARC thunks')
		}
		ios_runtime.swift_arc_code = 0
	}
}
