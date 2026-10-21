// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftErrorCodeFailure {}
fn (_ &SwiftErrorCodeFailure) msg() string { return 'iOS: invalid or inactive Swift Error code getter' }
fn (_ &SwiftErrorCodeFailure) code() int { return 1 }
__global swift_error_code_failure_value = SwiftErrorCodeFailure{}
fn swift_error_code_failure() IError { return unsafe { &swift_error_code_failure_value } }
type SwiftErrorCodeTag = fn (u64,u64) u32

fn swift_error_code_active() ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return swift_error_code_failure()
	}
}

// Borrowed readable ABI spans: metadata's first word, and for kind 0x201
// its preceding VWT pointer and 96-byte table. The tag witness owns the value
// layout contract (including zero-sized Self). Native Swift returns one for
// every other kind, including Optional, without reading Self or a VWT.
fn swift_error_code_checked(source u64, metadata u64) !u64 {
	swift_error_code_active()!
	if metadata < 8 || metadata & 7 != 0 || metadata > ~u64(0) - 7 {
		return swift_error_code_failure()
	}
	if read64(metadata) != 0x201 { return 1 }
	witness := read64(metadata - 8)
	if witness == 0 || witness & 7 != 0 || witness > ~u64(0) - 95 {
		return swift_error_code_failure()
	}
	entry := read64(witness + 88)
	if entry == 0 || entry & 3 != 0 { return swift_error_code_failure() }
	tag := unsafe { SwiftErrorCodeTag(voidptr(entry)) }
	// No registry lock crosses the borrowed value witness. Its UInt32 result
	// zero-extends into Swift.Int, including tags with bit31 set.
	return u64(tag(source, metadata))
}

fn swift_error_code(source u64, metadata u64) u64 {
	return swift_error_code_checked(source, metadata) or { panic(err) }
}

fn swift_error_code_emit(code u64) {
	// Swift x0 metadata, x1 unused Error table, x20 borrowed Self -> V/C.
	write32(code, 0xaa0003e1)
	write32(code + 4, 0xaa1403e0)
	write32(code + 8, 0x58000050)
	write32(code + 12, 0xd61f0200)
	unsafe { *(&u64(code + 16)) = u64(voidptr(swift_error_code)) }
}

fn swift_error_code_entry() !u64 {
	$if !arm64 { return swift_error_code_failure() }
	swift_error_code_active()!
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	swift_error_code_active()!
	return swift_error_metadata_arena() + 160
}
