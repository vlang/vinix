// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftUIEnvironmentTransformFailure {}
fn (_ &SwiftUIEnvironmentTransformFailure) msg() string { return 'iOS: SwiftUI environment transform descriptor requires active sealed storage' }
fn (_ &SwiftUIEnvironmentTransformFailure) code() int { return 1 }
__global swiftui_environment_transform_failure_value = SwiftUIEnvironmentTransformFailure{}
fn swiftui_environment_transform_failure() IError { return unsafe { &swiftui_environment_transform_failure_value } }

// Supply nominal identity and the unconstrained Value parameter only. A real
// specialization needs key-path/closure ownership and environment execution.
// Keep the generic bit so symbolic lookup rejects before reading the accessor.
fn swiftui_environment_transform_unavailable(request u64, value u64) SwiftAssociatedMetadata {
	panic('iOS: SwiftUI environment transform generic instantiation is not implemented')
}

fn swiftui_environment_transform_arena_checked() !u64 {
	$if !arm64 { return swiftui_environment_transform_failure() }
	if ios_runtime == unsafe { nil } { return swiftui_environment_transform_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swiftui_environment_transform_retired { return swiftui_environment_transform_failure() }
	if ios_runtime.swiftui_environment_transform_arena != 0 { return ios_runtime.swiftui_environment_transform_arena }
	if ios_runtime.swift_concurrency_retired { return swiftui_environment_transform_failure() }
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == voidptr(-1) { return swiftui_environment_transform_failure() }
	base := u64(arena); data := base + page
	descriptor := data; module_descriptor := data + 64
	write32(base, 0x58000050); write32(base + 4, 0xd61f0200)
	unsafe { *(&u64(base + 8)) = u64(voidptr(swiftui_environment_transform_unavailable)) }
	write32(descriptor, 0xd1) // Unique, generic struct.
	swift_protocol_relative(descriptor + 4, module_descriptor)
	swift_protocol_relative(descriptor + 8, data + 96)
	swift_protocol_relative(descriptor + 12, base)
	write32(descriptor + 20, 2); write32(descriptor + 24, 3)
	// No field reflection, instantiation cache, pattern or complete metadata.
	write32(descriptor + 36, 1) // One type parameter, zero requirements.
	write32(descriptor + 40, 1) // One key argument, no extra flags.
	write32(descriptor + 44, 0x80) // Ordinary key type parameter, padded.
	swift_protocol_relative(module_descriptor + 8, data + 80)
	C.memcpy(voidptr(data + 80), c'SwiftUI', 8)
	C.memcpy(voidptr(data + 96), c'_EnvironmentKeyTransformModifier', 33)
	C.__builtin___clear_cache(arena, voidptr(base + 16))
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page * 2)) != 0 { panic('iOS: cannot retire unsealed SwiftUI environment transform descriptor') }
		return swiftui_environment_transform_failure()
	}
	ios_runtime.swiftui_environment_transform_arena = base
	return base
}

// Called under the runtime lock after Swift owners and metadata users drain.
fn swiftui_environment_transform_stop() {
	ios_runtime.swiftui_environment_transform_retired = true
	if ios_runtime.swiftui_environment_transform_arena == 0 { return }
	if C.munmap(unsafe { voidptr(ios_runtime.swiftui_environment_transform_arena) }, usize(C.getpagesize()) * 2) != 0 { panic('iOS: cannot retire SwiftUI environment transform descriptor') }
	ios_runtime.swiftui_environment_transform_arena = 0
}

fn swiftui_environment_transform_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI32_EnvironmentKeyTransformModifierVMn' { return none }
	base := swiftui_environment_transform_arena_checked() or { return none }
	return base + u64(C.getpagesize())
}
