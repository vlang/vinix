// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftUIButtonNominalFailure {}
fn (_ &SwiftUIButtonNominalFailure) msg() string { return 'iOS: SwiftUI Button descriptor requires active sealed storage' }
fn (_ &SwiftUIButtonNominalFailure) code() int { return 1 }
__global swiftui_button_nominal_failure_value = SwiftUIButtonNominalFailure{}
fn swiftui_button_nominal_failure() IError { return unsafe { &swiftui_button_nominal_failure_value } }

// Supply nominal identity and Label: View. Specializing Button needs Label
// layout, its View witness and private action storage. Keep the generic bit so
// symbolic lookup rejects before attempting the nongeneric accessor ABI.
fn swiftui_button_nominal_unavailable(request u64, label u64, witness u64) SwiftAssociatedMetadata {
	panic('iOS: SwiftUI Button generic instantiation is not implemented')
}
fn swiftui_button_view_unavailable(table u64, metadata u64, arguments u64) {
	panic('iOS: SwiftUI Button View witness instantiation is not implemented')
}

fn swiftui_button_nominal_arena_checked() !u64 {
	$if !arm64 { return swiftui_button_nominal_failure() }
	if ios_runtime == unsafe { nil } { return swiftui_button_nominal_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swiftui_button_nominal_retired { return swiftui_button_nominal_failure() }
	if ios_runtime.swiftui_button_nominal_arena != 0 { return ios_runtime.swiftui_button_nominal_arena }
	if ios_runtime.swift_concurrency_retired { return swiftui_button_nominal_failure() }
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == voidptr(-1) { return swiftui_button_nominal_failure() }
	base := u64(arena); descriptor := base + page; module_descriptor := descriptor + 64
	write32(base, 0x58000050); write32(base + 4, 0xd61f0200)
	unsafe { *(&u64(base + 8)) = u64(voidptr(swiftui_button_nominal_unavailable)) }
	write32(descriptor, 0xd1) // Unique, generic struct.
	swift_protocol_relative(descriptor + 4, module_descriptor)
	swift_protocol_relative(descriptor + 8, descriptor + 96)
	swift_protocol_relative(descriptor + 12, base)
	write32(descriptor + 20, 3); write32(descriptor + 24, 4)
	// No reflection, instantiation cache, pattern or complete metadata.
	write32(descriptor + 36, 0x10001) // One type parameter, one requirement.
	write32(descriptor + 40, 2) // Label metadata and View witness key arguments.
	write32(descriptor + 44, 0x80) // Ordinary key type parameter, padded.
	view := descriptor + 128
	write32(descriptor + 48, 0x80) // Key protocol requirement: Label: View.
	swift_protocol_relative(descriptor + 52, descriptor + 272)
	swift_protocol_relative(descriptor + 56, view)
	C.memcpy(voidptr(descriptor + 272), c'x', 2)
	swift_protocol_relative(module_descriptor + 8, descriptor + 80)
	C.memcpy(voidptr(descriptor + 80), c'SwiftUI', 8)
	C.memcpy(voidptr(descriptor + 96), c'Button', 7)
	// The requirement names SwiftUI.View, including its Body: View signature.
	// The View declaration supplies no callable default implementations.
	write32(view, 0x30043); swift_protocol_relative(view + 4, module_descriptor)
	swift_protocol_relative(view + 8, descriptor + 224)
	write32(view + 12, 1); write32(view + 16, 6)
	swift_protocol_relative(view + 20, descriptor + 240)
	write32(view + 24, 0x80)
	swift_protocol_relative(view + 28, descriptor + 256)
	swift_protocol_relative(view + 32, view)
	C.memcpy(voidptr(descriptor + 224), c'View', 5)
	C.memcpy(voidptr(descriptor + 240), c'Body', 5)
	C.memcpy(voidptr(descriptor + 256), c'4Body', 5)
	unsafe { *(&u8(descriptor + 261)) = 1 }
	delta := u32(i32(i64(view) - i64(descriptor + 262)))
	for i in u64(0) .. 4 { unsafe { *(&u8(descriptor + 262 + i)) = u8(delta >> (i * 8)) } }
	C.memcpy(voidptr(descriptor + 266), c'Qz', 3)
	for i, flags in [u32(0xcade0008), 0x4b5f0007, 0xaeaf0001, 0x6ddd0001, 0x4cbb0001, 0xd1fd0013]! {
		write32(view + 36 + u64(i * 8), flags)
	}
	// Unconditional conformance with a generic witness table. Label: View is
	// already a nominal requirement, so there are no conditional arguments.
	// Preserve RequiresInstantiation; supply no pattern or writable cache.
	conformance := descriptor + 320
	swift_protocol_relative(conformance, view)
	swift_protocol_relative(conformance + 4, descriptor)
	write32(conformance + 12, 0x20000)
	write32(conformance + 16, 0x10000) // Zero copied words, no private words.
	swift_protocol_relative(conformance + 20, base + 16)
	write32(base + 16, 0x58000050); write32(base + 20, 0xd61f0200)
	unsafe { *(&u64(base + 24)) = u64(voidptr(swiftui_button_view_unavailable)) }
	C.__builtin___clear_cache(arena, voidptr(base + 32))
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(descriptor), usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page * 2)) != 0 { panic('iOS: cannot retire unsealed SwiftUI Button descriptor') }
		return swiftui_button_nominal_failure()
	}
	ios_runtime.swiftui_button_nominal_arena = base
	return base
}

// Called under the runtime lock after Swift owners and metadata users drain.
fn swiftui_button_nominal_stop() {
	ios_runtime.swiftui_button_nominal_retired = true
	if ios_runtime.swiftui_button_nominal_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swiftui_button_nominal_arena), usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire SwiftUI Button descriptor')
	}
	ios_runtime.swiftui_button_nominal_arena = 0
}

fn swiftui_button_nominal_symbol(symbol string) ?u64 {
	offset := match symbol {
		'_$s7SwiftUI6ButtonVMn' { u64(0) }
		'_$s7SwiftUI6ButtonVyxGAA4ViewAAMc' { u64(320) }
		else { return none }
	}
	base := swiftui_button_nominal_arena_checked() or { return none }
	return base + u64(C.getpagesize()) + offset
}
