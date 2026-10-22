// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftUIOpacityFailure {}
fn (_ &SwiftUIOpacityFailure) msg() string { return 'iOS: SwiftUI opacity witnesses require active sealed storage' }
fn (_ &SwiftUIOpacityFailure) code() int { return 1 }
__global swiftui_opacity_failure_value = SwiftUIOpacityFailure{}
fn swiftui_opacity_failure() IError { return unsafe { &swiftui_opacity_failure_value } }

fn swiftui_opacity_copy(destination u64, source u64, metadata u64) u64 {
	C.memmove(unsafe { voidptr(destination) }, unsafe { voidptr(source) }, 8)
	return destination
}
fn swiftui_opacity_destroy(value u64, metadata u64) {}
fn swiftui_opacity_enum_get(value u64, empty_cases u32, metadata u64) u32 {
	if empty_cases == 0 || unsafe { *(&u8(value + 8)) } == 0 { return 0 }
	mut bits := u32(0)
	for i in u64(0) .. 4 { bits |= u32(unsafe { *(&u8(value + i)) }) << (i * 8) }
	return bits + u32(1)
}
fn swiftui_opacity_enum_store(value u64, which_case u32, empty_cases u32, metadata u64) {
	if which_case != 0 {
		C.memset(unsafe { voidptr(value) }, 0, 8)
		bits := which_case - u32(1)
		for i in u64(0) .. 4 { unsafe { *(&u8(value + i)) = u8(bits >> (i * 8)) } }
	}
	if empty_cases != 0 { unsafe { *(&u8(value + 8)) = if which_case == 0 { u8(0) } else { u8(1) } } }
}
fn swiftui_opacity_graph_unavailable() {
	panic('iOS: SwiftUI opacity ViewModifier graph operations are not implemented')
}
fn swiftui_opacity_body_unavailable(associated u64, metadata u64, table u64) u64 {
	panic('iOS: SwiftUI opacity Body Never View conformance is not implemented')
}
fn swiftui_opacity_symbolic_relative(field u64, destination u64) {
	delta := i64(destination) - i64(field); assert delta >= -2147483648 && delta <= 2147483647
	bits := u32(i32(delta))
	for i in u64(0) .. 4 { unsafe { *(&u8(field + i)) = u8(bits >> (i * 8)) } }
}

fn swiftui_opacity_arena_checked() !u64 {
	$if !arm64 { return swiftui_opacity_failure() }
	if ios_runtime == unsafe { nil } { return swiftui_opacity_failure() }
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swiftui_opacity_retired { return swiftui_opacity_failure() }
	if ios_runtime.swiftui_opacity_arena != 0 { return ios_runtime.swiftui_opacity_arena }
	if ios_runtime.swift_concurrency_retired { return swiftui_opacity_failure() }
	page := u64(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == voidptr(-1) { return swiftui_opacity_failure() }
	base := u64(allocation); data := base + page
	metadata := data + 16; witness := data + 64; descriptor := data + 160
	module_descriptor := data + 192
	never := data + 264; never_witness := data + 288; never_descriptor := data + 384
	swift_module := data + 416; conformance := data + 464; table := data + 480
	modifier := data + 544; view := data + 640
	// Both nominal accessors return Complete in x0/x1 without a context read.
	for i, result in [metadata, never]! {
		entry := base + u64(i * 32)
		write32(entry, 0x58000080); write32(entry + 4, 0xd2800001); write32(entry + 8, 0xd65f03c0)
		unsafe { *(&u64(entry + 16)) = result }
	}
	for i, target in [u64(unsafe { voidptr(swiftui_opacity_graph_unavailable) }), u64(unsafe { voidptr(swiftui_opacity_body_unavailable) })]! {
		entry := base + 64 + u64(i * 16)
		write32(entry, 0x58000050); write32(entry + 4, 0xd61f0200)
		unsafe { *(&u64(entry + 8)) = target }
	}
	unsafe {
		*(&u64(metadata - 8)) = witness; *(&u64(metadata)) = 0x200; *(&u64(metadata + 8)) = descriptor
		*(&u64(never - 8)) = never_witness; *(&u64(never)) = 0x201; *(&u64(never + 8)) = never_descriptor
	}
	for i, function in [u64(unsafe { voidptr(swiftui_opacity_copy) }), u64(unsafe { voidptr(swiftui_opacity_destroy) }),
		u64(unsafe { voidptr(swiftui_opacity_copy) }), u64(unsafe { voidptr(swiftui_opacity_copy) }),
		u64(unsafe { voidptr(swiftui_opacity_copy) }), u64(unsafe { voidptr(swiftui_opacity_copy) }),
		u64(unsafe { voidptr(swiftui_opacity_enum_get) }), u64(unsafe { voidptr(swiftui_opacity_enum_store) })]! { unsafe { *(&u64(witness + u64(i * 8))) = function } }
	unsafe { *(&u64(witness + 64)) = 8; *(&u64(witness + 72)) = 8 }
	write32(witness + 80, 7)
	// Never has no value bytes. Its measured eight witnesses have the same
	// zero-size semantics as Void, including UInt32 tag-population wrapping.
	for i, function in [u64(unsafe { voidptr(swift_void_copy) }), u64(unsafe { voidptr(swift_void_destroy) }),
		u64(unsafe { voidptr(swift_void_copy) }), u64(unsafe { voidptr(swift_void_copy) }),
		u64(unsafe { voidptr(swift_void_copy) }), u64(unsafe { voidptr(swift_void_copy) }),
		u64(unsafe { voidptr(swift_void_enum_get) }), u64(unsafe { voidptr(swift_void_enum_store) })]! { unsafe { *(&u64(never_witness + u64(i * 8))) = function } }
	unsafe { *(&u64(never_witness + 72)) = 1 }
	write32(descriptor, 0x51); swift_protocol_relative(descriptor + 4, module_descriptor)
	swift_protocol_relative(descriptor + 8, data + 224); swift_protocol_relative(descriptor + 12, base)
	write32(descriptor + 20, 1); write32(descriptor + 24, 2)
	write32(never_descriptor, 0x52); swift_protocol_relative(never_descriptor + 4, swift_module)
	swift_protocol_relative(never_descriptor + 8, data + 440); swift_protocol_relative(never_descriptor + 12, base + 32)
	swift_protocol_relative(module_descriptor + 8, data + 208); swift_protocol_relative(swift_module + 8, data + 432)
	C.memcpy(voidptr(data + 208), c'SwiftUI', 8); C.memcpy(voidptr(data + 224), c'_OpacityEffect', 15)
	C.memcpy(voidptr(data + 432), c'Swift', 6); C.memcpy(voidptr(data + 440), c'Never', 6)
	C.memcpy(voidptr(data + 736), c'ViewModifier', 13); C.memcpy(voidptr(data + 752), c'Body', 5); C.memcpy(voidptr(data + 768), c'View', 5)
	// Preserve both protocol signatures: Self.Body: View. This is declaration
	// metadata; graph/default implementations remain unsupported.
	for i, protocol in [modifier, view]! {
		write32(protocol, 0x30043); swift_protocol_relative(protocol + 4, module_descriptor)
		swift_protocol_relative(protocol + 8, data + if i == 0 { u64(736) } else { u64(768) })
		write32(protocol + 12, 1); write32(protocol + 16, 6); swift_protocol_relative(protocol + 20, data + 752)
		write32(protocol + 24, 0x80); swift_protocol_relative(protocol + 28, data + 800 + u64(i * 32)); swift_protocol_relative(protocol + 32, view)
		path := data + 800 + u64(i * 32); C.memcpy(voidptr(path), c'4Body', 5)
		unsafe { *(&u8(path + 5)) = 1 }; swiftui_opacity_symbolic_relative(path + 6, protocol); C.memcpy(voidptr(path + 10), c'Qz', 3)
	}
	for i, flags in [u32(0xd0130008), 0x52130007, 0xc7420001, 0xb8560001, 0xf78f0001, 0x2b980011]! { write32(modifier + 36 + u64(i * 8), flags) }
	for i, flags in [u32(0xcade0008), 0x4b5f0007, 0xaeaf0001, 0x6ddd0001, 0x4cbb0001, 0xd1fd0013]! { write32(view + 36 + u64(i * 8), flags) }
	swift_protocol_relative(conformance, modifier); swift_protocol_relative(conformance + 4, descriptor); swift_protocol_relative(conformance + 8, table)
	unsafe { *(&u64(table)) = conformance; *(&u64(table + 8)) = (data + 896) | 1; *(&u64(table + 16)) = never }
	for i in u64(3) .. 7 { unsafe { *(&u64(table + i * 8)) = base + 64 } }
	// Associated-conformance witnesses use tagged FF 07 relative accessor data.
	unsafe { *(&u8(data + 896)) = 0xff; *(&u8(data + 897)) = 7 }
	swiftui_opacity_symbolic_relative(data + 898, base + 80)
	swiftui_view_opacity_emit(base + 128)
	swiftui_never_view_emit(base, data, never, never_descriptor, view)
	swiftui_view_protocol_emit(base, view)
	swiftui_uiview_representable_emit(base, data, view)
	C.__builtin___clear_cache(allocation, voidptr(base + 352))
	if C.mprotect(allocation, usize(page), C.PROT_READ | C.PROT_EXEC) != 0 || C.mprotect(voidptr(data), usize(page), C.PROT_READ) != 0 {
		if C.munmap(allocation, usize(page * 2)) != 0 { panic('iOS: cannot retire unsealed SwiftUI opacity witnesses') }
		return swiftui_opacity_failure()
	}
	ios_runtime.swiftui_opacity_arena = base
	return base
}
fn swiftui_opacity_symbol(symbol string) ?u64 {
	offset := match symbol {
		'_$ss5NeverO7SwiftUI4ViewACWP' { u64(960) }
		'_$s7SwiftUI14_OpacityEffectVAA12ViewModifierAAWP' { u64(480) }
		'_$s7SwiftUI14_OpacityEffectVMn' { u64(160) }
		else { return none }
	}
	base := swiftui_opacity_arena_checked() or { return none }
	return base + u64(C.getpagesize()) + offset
}
fn swiftui_opacity_stop() {
	ios_runtime.swiftui_opacity_retired = true
	if ios_runtime.swiftui_opacity_arena == 0 { return }
	if C.munmap(unsafe { voidptr(ios_runtime.swiftui_opacity_arena) }, usize(C.getpagesize()) * 2) != 0 { panic('iOS: cannot retire SwiftUI opacity witnesses') }
	ios_runtime.swiftui_opacity_arena = 0
}
