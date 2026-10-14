// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftDispatchMetadataFailure {}
fn (_ &SwiftDispatchMetadataFailure) msg() string { return 'iOS: Swift Dispatch metadata requires an active runtime and sealed storage' }
fn (_ &SwiftDispatchMetadataFailure) code() int { return 1 }
__global swift_dispatch_metadata_failure_value = SwiftDispatchMetadataFailure{}
fn swift_dispatch_metadata_failure() IError { return unsafe { &swift_dispatch_metadata_failure_value } }

// DispatchWorkItemFlags is a distinct nominal POD UInt word. The installed
// runtime's copy/take and destroy witnesses match Int's ownership-free bodies.
// Its tag store also writes a nonzero tag's payload when empty_cases is zero;
// the tag byte itself exists only when empty_cases is nonzero.
fn swift_dispatch_flags_enum_store(value u64, tag u32, empty_cases u32, metadata u64) {
	if tag != 0 { unsafe { *(&u64(value)) = u64(tag - 1) } }
	if empty_cases != 0 { unsafe { *(&u8(value + 8)) = if tag == 0 { u8(0) } else { u8(1) } } }
}

fn swift_dispatch_flags_arena_checked() !u64 {
	$if !arm64 { return swift_dispatch_metadata_failure() }
	if ios_runtime == unsafe { nil } { return swift_dispatch_metadata_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_dispatch_flags_retired { return swift_dispatch_metadata_failure() }
	if ios_runtime.swift_dispatch_flags_arena != 0 { return ios_runtime.swift_dispatch_flags_arena }
	// Reuse the canonical Swift module/Equatable identity. Their arenas outlive
	// this arena, and the recursive runtime lock permits their initialization.
	swift_integer_metadata()
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == unsafe { voidptr(-1) } { return swift_dispatch_metadata_failure() }
	base := u64(arena); data := base + page
	metadata := data + 16; witness := data + 64
	descriptor := data + 160; module_descriptor := data + 192
	// One sealed accessor returns MetadataResponse { metadata, Complete(0) }.
	// Both pages share an allocation so descriptor offsets remain signed i32.
	write32(base, 0x58000080)
	write32(base + 4, 0xd2800001)
	write32(base + 8, 0xd65f03c0)
	unsafe {
		*(&u64(base + 16)) = metadata
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x200
		*(&u64(metadata + 8)) = descriptor
	}
	for i, function in [u64(unsafe { voidptr(swift_integer_copy) }),
		u64(unsafe { voidptr(swift_integer_destroy) }), u64(unsafe { voidptr(swift_integer_copy) }),
		u64(unsafe { voidptr(swift_integer_copy) }), u64(unsafe { voidptr(swift_integer_copy) }),
		u64(unsafe { voidptr(swift_integer_copy) }), u64(unsafe { voidptr(swift_integer_enum_get) }),
		u64(unsafe { voidptr(swift_dispatch_flags_enum_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = function }
	}
	unsafe { *(&u64(witness + 64)) = 8; *(&u64(witness + 72)) = 8 }
	write32(witness + 80, 0x02000007) // POD, inline, bitwise-takable, alignment 8; no extra inhabitants.
	write32(descriptor, 0x51) // Unique nongeneric struct; no native initialization extensions advertised.
	swift_protocol_relative(descriptor + 4, module_descriptor)
	swift_protocol_relative(descriptor + 8, data + 224)
	swift_protocol_relative(descriptor + 12, base)
	// rawValue is the sole field at offset zero. Reflection is unsupported;
	// the descriptor deliberately has no field reflection record.
	write32(descriptor + 20, 1); write32(descriptor + 24, 2)
	swift_protocol_relative(module_descriptor + 8, data + 208)
	C.memcpy(voidptr(data + 208), c'Dispatch', 9)
	C.memcpy(voidptr(data + 224), c'DispatchWorkItemFlags', 22)
	integer_data := ios_runtime.swift_integer_arena + page
	swift_dispatch_algebra_build(base, data, integer_data + 192, integer_data + 432)
	swift_dispatch_qos_build(base, data)
	C.__builtin___clear_cache(arena, voidptr(base + 760))
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page * 2)) != 0 { panic('iOS: cannot retire unsealed Swift Dispatch metadata') }
		return swift_dispatch_metadata_failure()
	}
	ios_runtime.swift_dispatch_flags_arena = base
	return base
}

fn swift_dispatch_flags_stop() {
	// Runtime lock held, after metadata users and callbacks have drained.
	ios_runtime.swift_dispatch_flags_retired = true
	if ios_runtime.swift_dispatch_flags_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swift_dispatch_flags_arena), usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire Swift Dispatch metadata')
	}
	ios_runtime.swift_dispatch_flags_arena = 0
}

fn swift_dispatch_symbol(symbol string) !u64 {
	code_offset := match symbol {
		'_$s8Dispatch0A13WorkItemFlagsVMa' { u64(0) }
		'_$s8Dispatch0A3QoSV11unspecifiedACvgZ' { u64(704) }
		'_$s8Dispatch0A3QoSVMa' { u64(736) }
		'_$s8Dispatch0A13WorkItemFlagsVMn', '_$s8Dispatch0A13WorkItemFlagsVs10SetAlgebraAAMc', '_$s8Dispatch0A3QoSVMn' { ~u64(0) }
		else { return error('iOS: Swift Dispatch symbol is not implemented: ${symbol}') }
	}
	base := swift_dispatch_flags_arena_checked()!
	if code_offset != ~u64(0) { return base + code_offset }
	data_offset := match symbol {
		'_$s8Dispatch0A13WorkItemFlagsVMn' { u64(160) }
		'_$s8Dispatch0A3QoSVMn' { u64(1184) }
		else { u64(256) }
	}
	return base + u64(C.getpagesize()) + data_offset
}
