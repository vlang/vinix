// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftUILocalizedKeyFailure {}
fn (_ &SwiftUILocalizedKeyFailure) msg() string { return 'iOS: SwiftUI literal keys require active sealed storage' }
fn (_ &SwiftUILocalizedKeyFailure) code() int { return 1 }
__global swiftui_localized_key_failure_value = SwiftUILocalizedKeyFailure{}
fn swiftui_localized_key_failure() IError { return unsafe { &swiftui_localized_key_failure_value } }

fn swiftui_localized_key_arena_checked() !u64 {
	$if !arm64 { return swiftui_localized_key_failure() }
	if ios_runtime == unsafe { nil } { return swiftui_localized_key_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swiftui_localized_key_retired { return swiftui_localized_key_failure() }
	if ios_runtime.swiftui_localized_key_arena != 0 { return ios_runtime.swiftui_localized_key_arena }
	if ios_runtime.swift_concurrency_retired { return swiftui_localized_key_failure() }
	empty := swift_array_empty()
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == voidptr(-1) { return swiftui_localized_key_failure() }
	base := u64(allocation)
	// Consuming String x0/x1 is transferred without a load, copy or retain.
	// Swift returns this frozen aggregate in x0/x1/w2/x3, unlike C's x8 result.
	write32(base, 0xd2800002) // mov x2, #0: hasFormatting = false.
	write32(base + 4, 0x58000063) // ldr x3, literal at +16: empty arguments.
	write32(base + 8, 0xd65f03c0) // ret, preserving x8 and x20/x21.
	write32(base + 12, 0xd503201f)
	unsafe { *(&u64(base + 16)) = empty }
	C.__builtin___clear_cache(allocation, voidptr(base + 24))
	if C.mprotect(allocation, page, C.PROT_READ | C.PROT_EXEC) != 0 {
		if C.munmap(allocation, page) != 0 { panic('iOS: cannot retire unsealed SwiftUI literal key entry') }
		return swiftui_localized_key_failure()
	}
	ios_runtime.swiftui_localized_key_arena = base
	return base
}

fn swiftui_localized_key_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI18LocalizedStringKeyV13stringLiteralACSS_tcfC' { return none }
	return swiftui_localized_key_arena_checked() or { return none }
}

// Quiescent shutdown, before the referenced empty Array singleton retires.
fn swiftui_localized_key_stop() {
	ios_runtime.swiftui_localized_key_retired = true
	if ios_runtime.swiftui_localized_key_arena == 0 { return }
	if C.munmap(unsafe { voidptr(ios_runtime.swiftui_localized_key_arena) }, usize(C.getpagesize())) != 0 { panic('iOS: cannot retire SwiftUI literal key entry') }
	ios_runtime.swiftui_localized_key_arena = 0
}
