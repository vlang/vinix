// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftUIVStackFailure {}
fn (_ &SwiftUIVStackFailure) msg() string { return 'iOS: SwiftUI VStack metadata requires active sealed storage' }
fn (_ &SwiftUIVStackFailure) code() int { return 1 }
__global swiftui_vstack_failure_value = SwiftUIVStackFailure{}
fn swiftui_vstack_failure() IError { return unsafe { &swiftui_vstack_failure_value } }

// Frozen _VStackLayout: an alignment word and Optional<CGFloat> occupy 17
// bytes. Its 24-byte stride includes seven padding bytes that are not copied.
fn swiftui_vstack_copy(destination u64, source u64, metadata u64) u64 {
	C.memmove(unsafe { voidptr(destination) }, unsafe { voidptr(source) }, 17)
	return destination
}
fn swiftui_vstack_destroy(value u64, metadata u64) {}

fn swiftui_vstack_enum_get(value u64, empty_cases u32, metadata u64) u32 {
	if empty_cases == 0 || unsafe { *(&u8(value + 17)) } == 0 { return 0 }
	mut bits := u32(0)
	for i in u64(0) .. 4 { bits |= u32(unsafe { *(&u8(value + i)) }) << (i * 8) }
	return bits + u32(1)
}
fn swiftui_vstack_enum_store(value u64, which_case u32, empty_cases u32, metadata u64) {
	// Native witnesses write a nonzero case's 17-byte payload even when the
	// empty-case population is zero. Only nonzero populations write byte 17.
	if which_case != 0 {
		C.memset(unsafe { voidptr(value) }, 0, 17)
		bits := which_case - u32(1)
		for i in u64(0) .. 4 { unsafe { *(&u8(value + i)) = u8(bits >> (i * 8)) } }
	}
	if empty_cases != 0 { unsafe { *(&u8(value + 17)) = if which_case == 0 { u8(0) } else { u8(1) } } }
}

fn swiftui_vstack_arena_checked() !u64 {
	$if !arm64 { return swiftui_vstack_failure() }
	if ios_runtime == unsafe { nil } { return swiftui_vstack_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swiftui_vstack_retired { return swiftui_vstack_failure() }
	if ios_runtime.swiftui_vstack_arena != 0 { return ios_runtime.swiftui_vstack_arena }
	if ios_runtime.swift_concurrency_retired { return swiftui_vstack_failure() }
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == voidptr(-1) { return swiftui_vstack_failure() }
	base := u64(arena); data := base + page
	metadata := data + 16; witness := data + 64
	descriptor := data + 160; module_descriptor := data + 192
	// Complete MetadataResponse in x0/x1 for every request, with no context use.
	write32(base, 0x58000080); write32(base + 4, 0xd2800001); write32(base + 8, 0xd65f03c0)
	unsafe {
		*(&u64(base + 16)) = metadata
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x200
		*(&u64(metadata + 8)) = descriptor
	}
	write32(metadata + 20, 8) // Field offsets: alignment=0, spacing=8.
	for i, function in [u64(unsafe { voidptr(swiftui_vstack_copy) }),
		u64(unsafe { voidptr(swiftui_vstack_destroy) }), u64(unsafe { voidptr(swiftui_vstack_copy) }),
		u64(unsafe { voidptr(swiftui_vstack_copy) }), u64(unsafe { voidptr(swiftui_vstack_copy) }),
		u64(unsafe { voidptr(swiftui_vstack_copy) }), u64(unsafe { voidptr(swiftui_vstack_enum_get) }),
		u64(unsafe { voidptr(swiftui_vstack_enum_store) })]! { unsafe { *(&u64(witness + u64(i * 8))) = function } }
	unsafe { *(&u64(witness + 64)) = 17; *(&u64(witness + 72)) = 24 }
	write32(witness + 80, 7) // POD, inline, bitwise-takable, alignment8, zero extra inhabitants.
	write32(descriptor, 0x51)
	swift_protocol_relative(descriptor + 4, module_descriptor)
	swift_protocol_relative(descriptor + 8, data + 224)
	swift_protocol_relative(descriptor + 12, base)
	// Field reflection and SwiftUI layout/view conformances remain unsupported.
	write32(descriptor + 20, 2); write32(descriptor + 24, 2)
	swift_protocol_relative(module_descriptor + 8, data + 208)
	C.memcpy(voidptr(data + 208), c'SwiftUI', 8)
	C.memcpy(voidptr(data + 224), c'_VStackLayout', 14)
	C.__builtin___clear_cache(arena, voidptr(base + 24))
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page * 2)) != 0 { panic('iOS: cannot retire unsealed SwiftUI metadata') }
		return swiftui_vstack_failure()
	}
	ios_runtime.swiftui_vstack_arena = base
	return base
}

// Called under the runtime lock after owners/callbacks and Array metadata drain.
fn swiftui_vstack_stop() {
	ios_runtime.swiftui_vstack_retired = true
	if ios_runtime.swiftui_vstack_arena == 0 { return }
	if C.munmap(unsafe { voidptr(ios_runtime.swiftui_vstack_arena) }, usize(C.getpagesize()) * 2) != 0 { panic('iOS: cannot retire SwiftUI metadata') }
	ios_runtime.swiftui_vstack_arena = 0
}

fn swiftui_vstack_symbol(symbol string) ?u64 {
	if symbol != '_$s7SwiftUI13_VStackLayoutVMn' { return none }
	base := swiftui_vstack_arena_checked() or { return none }
	return base + u64(C.getpagesize()) + 160
}
