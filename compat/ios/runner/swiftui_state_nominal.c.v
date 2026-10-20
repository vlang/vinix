// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftUIStateNominalFailure {}
fn (_ &SwiftUIStateNominalFailure) msg() string { return 'iOS: SwiftUI State descriptor requires active sealed storage' }
fn (_ &SwiftUIStateNominalFailure) code() int { return 1 }
__global swiftui_state_nominal_failure_value = SwiftUIStateNominalFailure{}
fn swiftui_state_nominal_failure() IError { return unsafe { &swiftui_state_nominal_failure_value } }

// Supply nominal identity and the unconstrained Value parameter. Specializing
// State needs Value layout/ownership and optional AnyLocation metadata. Keep
// the generic bit so symbolic lookup rejects before using a nongeneric ABI.
fn swiftui_state_nominal_unavailable(request u64, value u64) SwiftAssociatedMetadata {
	panic('iOS: SwiftUI State generic instantiation is not implemented')
}

fn swiftui_state_nominal_arena_checked() !u64 {
	$if !arm64 { return swiftui_state_nominal_failure() }
	if ios_runtime == unsafe { nil } { return swiftui_state_nominal_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swiftui_state_nominal_retired { return swiftui_state_nominal_failure() }
	if ios_runtime.swiftui_state_nominal_arena != 0 { return ios_runtime.swiftui_state_nominal_arena }
	if ios_runtime.swift_concurrency_retired { return swiftui_state_nominal_failure() }
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == voidptr(-1) { return swiftui_state_nominal_failure() }
	base := u64(arena); descriptor := base + page; module_descriptor := descriptor + 64
	write32(base, 0x58000050); write32(base + 4, 0xd61f0200)
	unsafe { *(&u64(base + 8)) = u64(voidptr(swiftui_state_nominal_unavailable)) }
	write32(descriptor, 0xd1) // Unique, generic struct.
	swift_protocol_relative(descriptor + 4, module_descriptor)
	swift_protocol_relative(descriptor + 8, descriptor + 96)
	swift_protocol_relative(descriptor + 12, base)
	write32(descriptor + 20, 2); write32(descriptor + 24, 3)
	// No reflection, instantiation cache, pattern or complete metadata.
	write32(descriptor + 36, 1) // One type parameter, zero requirements.
	write32(descriptor + 40, 1) // One key argument, no extra flags.
	write32(descriptor + 44, 0x80) // Ordinary key type parameter, padded.
	swift_protocol_relative(module_descriptor + 8, descriptor + 80)
	C.memcpy(voidptr(descriptor + 80), c'SwiftUI', 8)
	C.memcpy(voidptr(descriptor + 96), c'State', 6)
	C.__builtin___clear_cache(arena, voidptr(base + 16))
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(descriptor), usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page * 2)) != 0 { panic('iOS: cannot retire unsealed SwiftUI State descriptor') }
		return swiftui_state_nominal_failure()
	}
	ios_runtime.swiftui_state_nominal_arena = base
	return base
}

// Called under the runtime lock after Swift owners and metadata users drain.
fn swiftui_state_nominal_stop() {
	ios_runtime.swiftui_state_nominal_retired = true
	if ios_runtime.swiftui_state_nominal_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swiftui_state_nominal_arena), usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire SwiftUI State descriptor')
	}
	ios_runtime.swiftui_state_nominal_arena = 0
}

fn swiftui_state_nominal_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI5StateVMn' { return none }
	base := swiftui_state_nominal_arena_checked() or { return none }
	return base + u64(C.getpagesize())
}
