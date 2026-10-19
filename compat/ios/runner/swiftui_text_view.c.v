// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftUITextViewFailure {}
fn (_ &SwiftUITextViewFailure) msg() string { return 'iOS: SwiftUI Text View table requires active sealed storage' }
fn (_ &SwiftUITextViewFailure) code() int { return 1 }
__global swiftui_text_view_failure_value = SwiftUITextViewFailure{}
fn swiftui_text_view_failure() IError { return unsafe { &swiftui_text_view_failure_value } }

// Text shares nominal identity with its complete value metadata. Never's
// metadata/conformance and SwiftUI graph execution remain unsupported.
fn swiftui_text_view_never_unavailable(request u64) SwiftAssociatedMetadata {
	panic('iOS: SwiftUI Text Body Never metadata is not implemented')
}
fn swiftui_text_view_graph_unavailable() {
	panic('iOS: SwiftUI Text View graph operations are not implemented')
}
fn swiftui_text_view_body_unavailable(associated u64, metadata u64, table u64) u64 {
	panic('iOS: SwiftUI Text Body Never View conformance is not implemented')
}
fn swiftui_text_view_relative_bytes(field u64, destination u64) {
	delta := i64(destination) - i64(field)
	assert delta >= -2147483648 && delta <= 2147483647
	bits := u32(i32(delta))
	for i in u64(0) .. 4 { unsafe { *(&u8(field + i)) = u8(bits >> (i * 8)) } }
}

fn swiftui_text_view_arena_checked() !u64 {
	$if !arm64 { return swiftui_text_view_failure() }
	if ios_runtime == unsafe { nil } { return swiftui_text_view_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swiftui_text_view_retired { return swiftui_text_view_failure() }
	if ios_runtime.swiftui_text_view_arena != 0 { return ios_runtime.swiftui_text_view_arena }
	if ios_runtime.swift_concurrency_retired { return swiftui_text_view_failure() }
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == voidptr(-1) { return swiftui_text_view_failure() }
	base := u64(arena); data := base + page
	for i, target in [u64(0), u64(unsafe { voidptr(swiftui_text_view_never_unavailable) }),
		u64(unsafe { voidptr(swiftui_text_view_graph_unavailable) }),
		u64(unsafe { voidptr(swiftui_text_view_body_unavailable) })]! {
		entry := base + u64(i * 16)
		if i == 0 { continue }
		write32(entry, 0x58000050); write32(entry + 4, 0xd61f0200)
		unsafe { *(&u64(entry + 8)) = target }
	}
	// Native Text has two fields, offset vector word two, no generic arguments.
	write32(data, 0x51)
	swift_protocol_relative(data + 4, data + 64)
	swift_protocol_relative(data + 8, data + 96)
	swift_protocol_relative(data + 12, base + 64)
	write32(data + 20, 2); write32(data + 24, 2)
	swift_protocol_relative(data + 72, data + 80)
	C.memcpy(voidptr(data + 80), c'SwiftUI', 8)
	C.memcpy(voidptr(data + 96), c'Text', 5)
	write32(data + 112, 0x52)
	swift_protocol_relative(data + 116, data + 144)
	swift_protocol_relative(data + 120, data + 168)
	swift_protocol_relative(data + 124, base + 16)
	swift_protocol_relative(data + 152, data + 160)
	C.memcpy(voidptr(data + 160), c'Swift', 6)
	C.memcpy(voidptr(data + 168), c'Never', 6)
	unsafe { *(&u64(data + 184)) = data; *(&u64(data + 192)) = data + 112 }
	view := data + 208
	write32(view, 0x30043)
	swift_protocol_relative(view + 4, data + 64)
	swift_protocol_relative(view + 8, data + 304)
	write32(view + 12, 1); write32(view + 16, 6)
	swift_protocol_relative(view + 20, data + 320)
	write32(view + 24, 0x80)
	swift_protocol_relative(view + 28, data + 336)
	swift_protocol_relative(view + 32, view)
	C.memcpy(voidptr(data + 304), c'View', 5)
	C.memcpy(voidptr(data + 320), c'Body', 5)
	C.memcpy(voidptr(data + 336), c'4Body', 5)
	unsafe { *(&u8(data + 341)) = 2; *(&u64(data + 480)) = view }
	swiftui_text_view_relative_bytes(data + 342, data + 480)
	C.memcpy(voidptr(data + 346), c'Qz', 3)
	for i, flags in [u32(0xcade0008), 0x4b5f0007, 0xaeaf0001, 0x6ddd0001, 0x4cbb0001, 0xd1fd0013]! {
		write32(view + 36 + u64(i * 8), flags)
	}
	conformance := data + 352; table := data + 384
	swift_protocol_relative(conformance, view)
	// Native type-reference kind is IndirectTypeDescriptor (flags bit 3).
	swift_protocol_relative(conformance + 4, data + 184)
	swift_protocol_relative(conformance + 8, table)
	write32(conformance + 12, 8)
	unsafe {
		*(&u64(table)) = conformance
		*(&u64(table + 8)) = (data + 448) | 1
		*(&u64(table + 16)) = (data + 464) | 1
		*(&u8(data + 448)) = 0xff; *(&u8(data + 449)) = 7
		*(&u8(data + 464)) = 2
	}
	swiftui_text_view_relative_bytes(data + 450, base + 48)
	// A tagged symbolic name referring indirectly to the Never descriptor.
	swiftui_text_view_relative_bytes(data + 465, data + 192)
	for i in u64(3) .. 7 { unsafe { *(&u64(table + i * 8)) = base + 32 } }
	swiftui_text_metadata_emit(base, data)
	C.__builtin___clear_cache(arena, voidptr(base + 120))
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page * 2)) != 0 { panic('iOS: cannot retire unsealed SwiftUI Text View table') }
		return swiftui_text_view_failure()
	}
	ios_runtime.swiftui_text_view_arena = base
	return base
}

// Runtime lock held; Swift workers, buffers, collections and callbacks drained.
fn swiftui_text_view_stop() {
	ios_runtime.swiftui_text_view_retired = true
	if ios_runtime.swiftui_text_view_arena == 0 { return }
	if C.munmap(unsafe { voidptr(ios_runtime.swiftui_text_view_arena) }, usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire SwiftUI Text View table')
	}
	ios_runtime.swiftui_text_view_arena = 0
}

fn swiftui_text_view_symbol(symbol string) ?u64 {
	offset := match symbol {
		'_$s7SwiftUI4TextVMn' { u64(0) }
		'_$s7SwiftUI4TextVN' { u64(512) }
		'_$s7SwiftUI4TextVAA4ViewAAWP' { u64(384) }
		else { return none }
	}
	base := swiftui_text_view_arena_checked() or { return none }
	return base + u64(C.getpagesize()) + offset
}
