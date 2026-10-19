// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftUIModifiedFailure {}
fn (_ &SwiftUIModifiedFailure) msg() string { return 'iOS: SwiftUI ModifiedContent descriptor requires active sealed storage' }
fn (_ &SwiftUIModifiedFailure) code() int { return 1 }
__global swiftui_modified_failure_value = SwiftUIModifiedFailure{}
fn swiftui_modified_failure() IError { return unsafe { &swiftui_modified_failure_value } }

// Only nominal identity and the unconstrained generic signature are supplied.
// Layout and ownership depend on both parameters; no Complete metadata exists.
fn swiftui_modified_unavailable(request u64, content u64, modifier u64) SwiftAssociatedMetadata {
	panic('iOS: SwiftUI ModifiedContent generic instantiation is not implemented')
}

fn swiftui_modified_arena_checked() !u64 {
	$if !arm64 { return swiftui_modified_failure() }
	if ios_runtime == unsafe { nil } { return swiftui_modified_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swiftui_modified_retired { return swiftui_modified_failure() }
	if ios_runtime.swiftui_modified_arena != 0 { return ios_runtime.swiftui_modified_arena }
	if ios_runtime.swift_concurrency_retired { return swiftui_modified_failure() }
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == voidptr(-1) { return swiftui_modified_failure() }
	base := u64(arena); data := base + page
	descriptor := data; module_descriptor := data + 64
	// Tail-call the diagnostic without reading generic arguments. The generic
	// bit also makes mangled lookup reject before trying the nongeneric ABI.
	write32(base, 0x58000050); write32(base + 4, 0xd61f0200)
	unsafe { *(&u64(base + 8)) = u64(voidptr(swiftui_modified_unavailable)) }
	write32(descriptor, 0xd1) // Unique, generic struct.
	swift_protocol_relative(descriptor + 4, module_descriptor)
	swift_protocol_relative(descriptor + 8, data + 96)
	swift_protocol_relative(descriptor + 12, base)
	write32(descriptor + 20, 2); write32(descriptor + 24, 4)
	// No field reflection, instantiation cache or default instantiation pattern.
	write32(descriptor + 36, 2) // Two type parameters, zero requirements.
	write32(descriptor + 40, 2) // Two key arguments, no extra flags.
	write32(descriptor + 44, 0x8080) // Ordinary key type parameters, padded.
	swift_protocol_relative(module_descriptor + 8, data + 80)
	C.memcpy(voidptr(data + 80), c'SwiftUI', 8)
	C.memcpy(voidptr(data + 96), c'ModifiedContent', 16)
	C.__builtin___clear_cache(arena, voidptr(base + 16))
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page * 2)) != 0 { panic('iOS: cannot retire unsealed SwiftUI ModifiedContent descriptor') }
		return swiftui_modified_failure()
	}
	ios_runtime.swiftui_modified_arena = base
	return base
}

// Called under the runtime lock after Swift owners and metadata users drain.
fn swiftui_modified_stop() {
	ios_runtime.swiftui_modified_retired = true
	if ios_runtime.swiftui_modified_arena == 0 { return }
	if C.munmap(unsafe { voidptr(ios_runtime.swiftui_modified_arena) }, usize(C.getpagesize()) * 2) != 0 { panic('iOS: cannot retire SwiftUI ModifiedContent descriptor') }
	ios_runtime.swiftui_modified_arena = 0
}

fn swiftui_modified_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI15ModifiedContentVMn' { return none }
	base := swiftui_modified_arena_checked() or { return none }
	return base + u64(C.getpagesize())
}
