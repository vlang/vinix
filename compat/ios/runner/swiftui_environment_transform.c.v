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

fn swiftui_environment_transform_graph_unavailable() {
	panic('iOS: SwiftUI environment transform ViewModifier graph operations are not implemented')
}
fn swiftui_environment_transform_body_unavailable(associated u64, metadata u64, table u64) u64 {
	panic('iOS: SwiftUI environment transform Body Never View conformance is not implemented')
}
fn swiftui_environment_transform_relative_bytes(field u64, destination u64) {
	delta := i64(destination) - i64(field); assert delta >= -2147483648 && delta <= 2147483647
	bits := u32(i32(delta))
	for i in u64(0) .. 4 { unsafe { *(&u8(field + i)) = u8(bits >> (i * 8)) } }
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
	// The native unconditional conformance has a fixed seven-word table, even
	// though the nominal type is generic. Do not invent a generic instantiator.
	conformance := data + 160; table := data + 192
	modifier := data + 256; view := data + 352
	swift_protocol_relative(conformance, modifier)
	swift_protocol_relative(conformance + 4, descriptor)
	swift_protocol_relative(conformance + 8, table)
	for i, protocol in [modifier, view]! {
		write32(protocol, 0x30043); swift_protocol_relative(protocol + 4, module_descriptor)
		swift_protocol_relative(protocol + 8, data + 448 + u64(i * 16))
		write32(protocol + 12, 1); write32(protocol + 16, 6)
		swift_protocol_relative(protocol + 20, data + 480)
		write32(protocol + 24, 0x80)
		swift_protocol_relative(protocol + 28, data + 496 + u64(i * 32))
		swift_protocol_relative(protocol + 32, view)
		path := data + 496 + u64(i * 32); C.memcpy(voidptr(path), c'4Body', 5)
		unsafe { *(&u8(path + 5)) = 1 }
		swiftui_environment_transform_relative_bytes(path + 6, protocol)
		C.memcpy(voidptr(path + 10), c'Qz', 3)
	}
	C.memcpy(voidptr(data + 448), c'ViewModifier', 13)
	C.memcpy(voidptr(data + 464), c'View', 5); C.memcpy(voidptr(data + 480), c'Body', 5)
	for i, flags in [u32(0xd0130008), 0x52130007, 0xc7420001, 0xb8560001, 0xf78f0001, 0x2b980011]! { write32(modifier + 36 + u64(i * 8), flags) }
	for i, flags in [u32(0xcade0008), 0x4b5f0007, 0xaeaf0001, 0x6ddd0001, 0x4cbb0001, 0xd1fd0013]! { write32(view + 36 + u64(i * 8), flags) }
	for i, target in [u64(unsafe { voidptr(swiftui_environment_transform_graph_unavailable) }), u64(unsafe { voidptr(swiftui_environment_transform_body_unavailable) })]! {
		entry := base + 16 + u64(i * 16)
		write32(entry, 0x58000050); write32(entry + 4, 0xd61f0200)
		unsafe { *(&u64(entry + 8)) = target }
	}
	unsafe {
		*(&u64(table)) = conformance
		*(&u64(table + 8)) = (data + 560) | 1
		*(&u64(table + 16)) = (data + 576) | 1
		*(&u8(data + 560)) = 0xff; *(&u8(data + 561)) = 7
	}
	swiftui_environment_transform_relative_bytes(data + 562, base + 32)
	// Body is Never. The existing associated-type decoder rejects this mangled
	// name explicitly; it must not mistake a tagged data slot for callable code.
	C.memcpy(voidptr(data + 576), c's5NeverO', 9)
	for i in u64(3) .. 7 { unsafe { *(&u64(table + i * 8)) = base + 16 } }
	C.__builtin___clear_cache(arena, voidptr(base + 48))
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
	offset := match symbol {
		'_$s7SwiftUI32_EnvironmentKeyTransformModifierVMn' { u64(0) }
		'_$s7SwiftUI32_EnvironmentKeyTransformModifierVyxGAA04ViewF0AAMc' { u64(160) }
		else { return none }
	}
	base := swiftui_environment_transform_arena_checked() or { return none }
	return base + u64(C.getpagesize()) + offset
}
