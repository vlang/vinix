// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftUITreeFailure {}
fn (_ &SwiftUITreeFailure) msg() string { return 'iOS: SwiftUI Tree descriptor requires active sealed storage' }
fn (_ &SwiftUITreeFailure) code() int { return 1 }
__global swiftui_tree_failure_value = SwiftUITreeFailure{}
fn swiftui_tree_failure() IError { return unsafe { &swiftui_tree_failure_value } }

// Only nominal identity and the generic signature are supplied. Tree's value
// layout and ownership depend on both parameters; no Complete metadata exists.
fn swiftui_tree_unavailable(request u64, root u64, content u64, conformance u64) SwiftAssociatedMetadata {
	panic('iOS: SwiftUI Tree generic instantiation is not implemented')
}

fn swiftui_tree_arena_checked() !u64 {
	$if !arm64 { return swiftui_tree_failure() }
	if ios_runtime == unsafe { nil } { return swiftui_tree_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swiftui_tree_retired { return swiftui_tree_failure() }
	if ios_runtime.swiftui_tree_arena != 0 { return ios_runtime.swiftui_tree_arena }
	if ios_runtime.swift_concurrency_retired { return swiftui_tree_failure() }
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == voidptr(-1) { return swiftui_tree_failure() }
	base := u64(arena); data := base + page
	descriptor := data; parent := data + 64; module_descriptor := data + 96
	protocol := data + 112
	// A metadata-access attempt tail-calls a diagnostic without inspecting any
	// generic arguments. Keep the generic bit so mangled lookup rejects first.
	write32(base, 0x58000050); write32(base + 4, 0xd61f0200)
	unsafe { *(&u64(base + 8)) = u64(voidptr(swiftui_tree_unavailable)) }
	write32(descriptor, 0xd1) // Unique, generic struct.
	swift_protocol_relative(descriptor + 4, parent)
	swift_protocol_relative(descriptor + 8, data + 176)
	swift_protocol_relative(descriptor + 12, base)
	write32(descriptor + 20, 2); write32(descriptor + 24, 5)
	// No field reflection, instantiation cache or default instantiation pattern.
	write32(descriptor + 36, 0x00010002) // NumParams=2, NumRequirements=1.
	write32(descriptor + 40, 3) // Three key arguments, no extra flags.
	write32(descriptor + 44, 0x8080) // Two ordinary key type parameters, padded.
	write32(descriptor + 48, 0x80) // Key protocol-conformance requirement.
	swift_protocol_relative(descriptor + 52, data + 240) // Root (mangled x).
	swift_protocol_relative(descriptor + 56, protocol)
	write32(parent, 0x52) // Nongeneric, empty namespace enum _VariadicView.
	swift_protocol_relative(parent + 4, module_descriptor)
	swift_protocol_relative(parent + 8, data + 184)
	swift_protocol_relative(module_descriptor + 8, data + 160)
	write32(protocol, 0x30043) // Unique Swift protocol, no class constraint.
	swift_protocol_relative(protocol + 4, module_descriptor)
	swift_protocol_relative(protocol + 8, data + 208)
	write32(protocol + 16, 1); write32(protocol + 24, 3) // Static getter requirement.
	// No default getter or conformances are provided by this descriptor export.
	C.memcpy(voidptr(data + 160), c'SwiftUI', 8)
	C.memcpy(voidptr(data + 176), c'Tree', 5)
	C.memcpy(voidptr(data + 184), c'_VariadicView', 14)
	C.memcpy(voidptr(data + 208), c'_VariadicView_Root', 19)
	C.memcpy(voidptr(data + 240), c'x', 2)
	C.__builtin___clear_cache(arena, voidptr(base + 16))
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page * 2)) != 0 { panic('iOS: cannot retire unsealed SwiftUI Tree descriptor') }
		return swiftui_tree_failure()
	}
	ios_runtime.swiftui_tree_arena = base
	return base
}

// Called under the runtime lock after Swift owners and metadata users drain.
fn swiftui_tree_stop() {
	ios_runtime.swiftui_tree_retired = true
	if ios_runtime.swiftui_tree_arena == 0 { return }
	if C.munmap(unsafe { voidptr(ios_runtime.swiftui_tree_arena) }, usize(C.getpagesize()) * 2) != 0 { panic('iOS: cannot retire SwiftUI Tree descriptor') }
	ios_runtime.swiftui_tree_arena = 0
}

fn swiftui_tree_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI13_VariadicViewO4TreeVMn' { return none }
	base := swiftui_tree_arena_checked() or { return none }
	return base + u64(C.getpagesize())
}
