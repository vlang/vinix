// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftLocalizedErrorProtocolFailure {}

fn (_ &SwiftLocalizedErrorProtocolFailure) msg() string {
	return 'iOS: Swift LocalizedError requires an active runtime and sealed storage'
}

fn (_ &SwiftLocalizedErrorProtocolFailure) code() int { return 1 }

__global swift_localized_error_protocol_failure_value = SwiftLocalizedErrorProtocolFailure{}

fn swift_localized_error_protocol_failure() IError {
	return unsafe { &swift_localized_error_protocol_failure_value }
}

fn swift_localized_error_protocol_arena_checked() !u64 {
	$if !arm64 { return swift_localized_error_protocol_failure() }
	if ios_runtime == unsafe { nil } { return swift_localized_error_protocol_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_localized_error_protocol_retired || ios_runtime.swift_concurrency_retired {
		return swift_localized_error_protocol_failure()
	}
	if ios_runtime.swift_localized_error_protocol_arena != 0 {
		return ios_runtime.swift_localized_error_protocol_arena
	}
	// Borrow canonical declarations under the recursive publication lock. This
	// arena retires before Foundation and before Error's metadata is unmapped.
	page := u64(C.getpagesize())
	foundation := swift_foundation_arena() + page + 64
	error_protocol := swift_error_metadata_arena() + page + 240
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == unsafe { voidptr(-1) } { return swift_localized_error_protocol_failure() }
	base := u64(arena)
	data := base + page
	write32(data, 0x30043) // Unique Swift protocol, unconstrained by class.
	swift_protocol_relative(data + 4, foundation)
	swift_protocol_relative(data + 8, data + 128)
	write32(data + 12, 1) // Self: Error.
	write32(data + 16, 5) // Inherited table followed by the four getters.
	write32(data + 24, 0x80)
	swift_protocol_relative(data + 28, data + 144)
	// Native uses a tagged indirect protocol reference, pointing at an Error
	// descriptor slot rather than embedding a second Error declaration.
	swift_protocol_relative(data + 32, data + 153)
	unsafe { *(&u64(data + 152)) = error_protocol }
	for i, flags in [u32(0), 0xb1700013, 0x636e0013, 0xa3140013, 0xadc30013]! {
		write32(data + 36 + u64(i * 8), flags)
		if i == 0 { continue }
		entry := base + u64((i - 1) * 16)
		// Apple's private protocol defaults and exported PAAE extension getters
		// are distinct. Both return nil String? in x0/x1 without reading inputs,
		// touching indirect output, changing preserved registers or owning Self.
		write32(entry, 0xd2800000)
		write32(entry + 4, 0xd2800001)
		write32(entry + 8, 0xd65f03c0)
		swift_protocol_relative(data + 40 + u64(i * 8), entry)
	}
	C.memcpy(voidptr(data + 128), c'LocalizedError', 15)
	C.memcpy(voidptr(data + 144), c'x', 2)
	C.__builtin___clear_cache(arena, voidptr(base + 60))
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page * 2)) != 0 {
			panic('iOS: cannot retire unsealed Swift LocalizedError declaration')
		}
		return swift_localized_error_protocol_failure()
	}
	ios_runtime.swift_localized_error_protocol_arena = base
	return base
}

fn swift_localized_error_protocol_stop() {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	ios_runtime.swift_localized_error_protocol_retired = true
	if ios_runtime.swift_localized_error_protocol_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swift_localized_error_protocol_arena),
		usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire Swift LocalizedError declaration')
	}
	ios_runtime.swift_localized_error_protocol_arena = 0
}

fn swift_localized_error_protocol_symbol(symbol string) ?u64 {
	page := u64(C.getpagesize())
	offset := match symbol {
		'_$s10Foundation14LocalizedErrorMp' { page }
		'_$s10Foundation14LocalizedErrorTL' { page + 28 }
		'_$s10Foundation14LocalizedErrorPs0C0Tb' { page + 36 }
		'_$s10Foundation14LocalizedErrorP16errorDescriptionSSSgvgTq' { page + 44 }
		'_$s10Foundation14LocalizedErrorP13failureReasonSSSgvgTq' { page + 52 }
		'_$s10Foundation14LocalizedErrorP18recoverySuggestionSSSgvgTq' { page + 60 }
		'_$s10Foundation14LocalizedErrorP10helpAnchorSSSgvgTq' { page + 68 }
		else { return none }
	}
	base := swift_localized_error_protocol_arena_checked() or { return none }
	return base + offset
}
