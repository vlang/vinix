// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftCustomDebugFailure {}

fn (_ &SwiftCustomDebugFailure) msg() string {
	return 'iOS: Swift CustomDebugStringConvertible requires an active runtime and sealed storage'
}

fn (_ &SwiftCustomDebugFailure) code() int { return 1 }

__global swift_custom_debug_failure_value = SwiftCustomDebugFailure{}

fn swift_custom_debug_failure() IError { return unsafe { &swift_custom_debug_failure_value } }

fn swift_custom_debug_arena_checked() !u64 {
	$if !arm64 {
		return swift_custom_debug_failure()
	}
	if ios_runtime == unsafe { nil } { return swift_custom_debug_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_custom_debug_retired || ios_runtime.swift_concurrency_retired {
		return swift_custom_debug_failure()
	}
	if ios_runtime.swift_custom_debug_arena != 0 { return ios_runtime.swift_custom_debug_arena }
	// Borrow the canonical Swift module while holding the recursive publication
	// lock. This declaration retires before Array releases that module's page.
	array := swift_array_arena()
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page), C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == unsafe { voidptr(-1) } { return swift_custom_debug_failure() }
	base := u64(arena)
	write32(base, 0x30043) // Unique Swift protocol, unconstrained by class.
	swift_protocol_relative(base + 4, array + page + 224)
	swift_protocol_relative(base + 8, base + 32)
	write32(base + 16, 1) // One requirement, no generic signature or associated types.
	write32(base + 24, 0x081a0013) // Native instance getter discriminator.
	// The default implementation rel32 remains zero: this is a declaration,
	// not a concrete conformance or a fallback debugDescription implementation.
	C.memcpy(voidptr(base + 32), c'CustomDebugStringConvertible', 29)
	if C.mprotect(arena, usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page)) != 0 {
			panic('iOS: cannot retire unsealed Swift CustomDebugStringConvertible declaration')
		}
		return swift_custom_debug_failure()
	}
	ios_runtime.swift_custom_debug_arena = base
	return base
}

fn swift_custom_debug_stop() {
	// Workers and callbacks have drained. Retire the declaration before its
	// borrowed Swift module, under the runtime publication lock.
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	ios_runtime.swift_custom_debug_retired = true
	if ios_runtime.swift_custom_debug_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swift_custom_debug_arena), usize(C.getpagesize())) != 0 {
		panic('iOS: cannot retire Swift CustomDebugStringConvertible declaration')
	}
	ios_runtime.swift_custom_debug_arena = 0
}

fn swift_custom_debug_symbol(symbol string) ?u64 {
	offset := match symbol {
		'_$ss28CustomDebugStringConvertibleMp' { 0 }
		'_$ss28CustomDebugStringConvertibleTL' { 16 }
		'_$ss28CustomDebugStringConvertibleP16debugDescriptionSSvgTq' { 24 }
		else { return none }
	}
	base := swift_custom_debug_arena_checked() or { return none }
	return base + u64(offset)
}
