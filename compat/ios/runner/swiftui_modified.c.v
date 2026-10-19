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
fn swiftui_modified_view_unavailable(table u64, metadata u64, arguments u64) {
	panic('iOS: SwiftUI ModifiedContent View witness instantiation is not implemented')
}
fn swiftui_modified_relative_bytes(field u64, destination u64) {
	delta := i64(destination) - i64(field); assert delta >= -2147483648 && delta <= 2147483647
	bits := u32(i32(delta))
	for i in u64(0) .. 4 { unsafe { *(&u8(field + i)) = u8(bits >> (i * 8)) } }
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
	// Conditional conformance declaration: Content: View, Modifier: ViewModifier.
	// Preserve the conditional/generic flags; ordinary witness lookup rejects
	// before reading metadata or arguments. No witness pattern is supplied.
	conformance := data + 128; view := data + 256; modifier := data + 352
	swift_protocol_relative(conformance, view)
	swift_protocol_relative(conformance + 4, descriptor)
	write32(conformance + 12, 0x20200)
	for i, protocol in [view, modifier]! {
		requirement := conformance + 16 + u64(i * 12)
		write32(requirement, 0x80)
		swift_protocol_relative(requirement + 4, data + 208 + u64(i * 8))
		swift_protocol_relative(requirement + 8, protocol)
		write32(protocol, 0x30043); swift_protocol_relative(protocol + 4, module_descriptor)
		swift_protocol_relative(protocol + 8, data + 448 + u64(i * 16))
		write32(protocol + 12, 1); write32(protocol + 16, 6)
		swift_protocol_relative(protocol + 20, data + 480)
		write32(protocol + 24, 0x80)
		swift_protocol_relative(protocol + 28, data + 496 + u64(i * 32))
		swift_protocol_relative(protocol + 32, view)
		path := data + 496 + u64(i * 32); C.memcpy(voidptr(path), c'4Body', 5)
		unsafe { *(&u8(path + 5)) = 1 }
		swiftui_modified_relative_bytes(path + 6, protocol)
		C.memcpy(voidptr(path + 10), c'Qz', 3)
	}
	C.memcpy(voidptr(data + 208), c'x', 2); C.memcpy(voidptr(data + 216), c'q_', 3)
	C.memcpy(voidptr(data + 448), c'View', 5); C.memcpy(voidptr(data + 464), c'ViewModifier', 13)
	C.memcpy(voidptr(data + 480), c'Body', 5)
	for i, flags in [u32(0xcade0008), 0x4b5f0007, 0xaeaf0001, 0x6ddd0001, 0x4cbb0001, 0xd1fd0013]! { write32(view + 36 + u64(i * 8), flags) }
	for i, flags in [u32(0xd0130008), 0x52130007, 0xc7420001, 0xb8560001, 0xf78f0001, 0x2b980011]! { write32(modifier + 36 + u64(i * 8), flags) }
	// A null pattern requires zero copied words. Retain two private conditional
	// arguments and RequiresInstantiation, but always fail before publication.
	// The ABI permits a null out-of-line cache; no writable cache is allocated.
	write32(conformance + 40, 0x00050000)
	swift_protocol_relative(conformance + 44, base + 16)
	write32(base + 16, 0x58000050); write32(base + 20, 0xd61f0200)
	unsafe { *(&u64(base + 24)) = u64(voidptr(swiftui_modified_view_unavailable)) }
	C.__builtin___clear_cache(arena, voidptr(base + 32))
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
	offset := match symbol {
		'_$s7SwiftUI15ModifiedContentVMn' { u64(0) }
		'_$s7SwiftUI15ModifiedContentVyxq_GAA4ViewA2aERzAA0E8ModifierR_rlMc' { u64(128) }
		else { return none }
	}
	base := swiftui_modified_arena_checked() or { return none }
	return base + u64(C.getpagesize()) + offset
}
