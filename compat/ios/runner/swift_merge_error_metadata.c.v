// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftMergeErrorMetadataFailure {}

fn (_ &SwiftMergeErrorMetadataFailure) msg() string {
	return 'iOS: Swift _MergeError metadata requires an active runtime and sealed storage'
}

fn (_ &SwiftMergeErrorMetadataFailure) code() int { return 1 }

__global swift_merge_error_metadata_failure_value = SwiftMergeErrorMetadataFailure{}

fn swift_merge_error_metadata_failure() IError {
	return unsafe { &swift_merge_error_metadata_failure_value }
}

// The frozen keyCollision case has no payload or discriminator bytes. Its
// enum-specific operations never inspect a value or metadata address.
fn swift_merge_error_tag(_value u64, _metadata u64) u32 { return 0 }

fn swift_merge_error_project(_value u64, _metadata u64) {}

fn swift_merge_error_inject(_value u64, _tag u32, _metadata u64) {}

// Unlike the empty tuple witnesses, this enum still uses one tag byte when
// the UInt32 payload-plus-empty-case count wraps at UINT32_MAX.
fn swift_merge_error_tag_bytes(cases u32) u32 {
	if cases == 0 { return 0 }
	if cases < 255 || cases == 0xffffffff { return 1 }
	return if cases < 65535 { u32(2) } else { u32(4) }
}

fn swift_merge_error_enum_get(value u64, cases u32, _metadata u64) u32 {
	mut tag := u32(0)
	for i in u32(0) .. swift_merge_error_tag_bytes(cases) {
		tag |= u32(unsafe { *(&u8(value + i)) }) << (i * 8)
	}
	return tag
}

fn swift_merge_error_enum_store(value u64, tag u32, cases u32, _metadata u64) {
	for i in u32(0) .. swift_merge_error_tag_bytes(cases) {
		unsafe { *(&u8(value + i)) = u8(tag >> (i * 8)) }
	}
}

fn swift_merge_error_metadata_arena_checked() !u64 {
	$if !arm64 {
		return swift_merge_error_metadata_failure()
	}
	if ios_runtime == unsafe { nil } { return swift_merge_error_metadata_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_merge_error_metadata_retired || ios_runtime.swift_concurrency_retired {
		return swift_merge_error_metadata_failure()
	}
	if ios_runtime.swift_merge_error_metadata_arena != 0 {
		return ios_runtime.swift_merge_error_metadata_arena
	}
	page := u64(C.getpagesize())
	protocol := swift_error_metadata_arena() + page + 240
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == unsafe { voidptr(-1) } { return swift_merge_error_metadata_failure() }
	base := u64(arena)
	data := base + page
	metadata := data + 16
	witness := data + 64
	descriptor := data + 192
	module_descriptor := data + 224
	// Complete MetadataResponse in x0/x1, independent of the request in x0.
	write32(base, 0x58000080)
	write32(base + 4, 0xd2800001)
	write32(base + 8, 0xd65f03c0)
	write32(base + 12, 0xd503201f)
	unsafe {
		*(&u64(base + 16)) = metadata
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x201 // Enum, distinct from Void/Optional/structs.
		*(&u64(metadata + 8)) = descriptor
	}
	for i, function in [u64(unsafe { voidptr(swift_void_copy) }),
		u64(unsafe { voidptr(swift_void_destroy) }), u64(unsafe { voidptr(swift_void_copy) }),
		u64(unsafe { voidptr(swift_void_copy) }), u64(unsafe { voidptr(swift_void_copy) }),
		u64(unsafe { voidptr(swift_void_copy) }), u64(unsafe { voidptr(swift_merge_error_enum_get) }),
		u64(unsafe { voidptr(swift_merge_error_enum_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = function }
	}
	unsafe {
		*(&u64(witness + 72)) = 1 // Size zero, stride one, alignment one.
		*(&u64(witness + 88)) = u64(voidptr(swift_merge_error_tag))
		*(&u64(witness + 96)) = u64(voidptr(swift_merge_error_project))
		*(&u64(witness + 104)) = u64(voidptr(swift_merge_error_inject))
	}
	write32(witness + 80, 0x00200000) // POD, inline, bitwise-takable, enum witnesses, no extra inhabitants.
	write32(descriptor, 0x52) // Unique nongeneric enum, no reflection/initialization extensions.
	swift_protocol_relative(descriptor + 4, module_descriptor)
	swift_protocol_relative(descriptor + 8, data + 256)
	swift_protocol_relative(descriptor + 12, base)
	write32(descriptor + 24, 1) // Zero payload cases, one empty case.
	swift_protocol_relative(module_descriptor + 8, data + 240)
	C.memcpy(voidptr(data + 240), c'Swift', 6)
	C.memcpy(voidptr(data + 256), c'_MergeError', 12)
	swift_merge_error_conformance_emit(base, data, protocol)
	C.__builtin___clear_cache(arena, voidptr(base + 128))
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page * 2)) != 0 {
			panic('iOS: cannot retire unsealed Swift _MergeError metadata')
		}
		return swift_merge_error_metadata_failure()
	}
	ios_runtime.swift_merge_error_metadata_arena = base
	ios_runtime.swift_merge_error_conformance_descriptor = data + 288
	return base
}

fn swift_merge_error_metadata_stop() {
	// Runtime lock held after metadata users, values and callbacks have drained.
	ios_runtime.swift_merge_error_metadata_retired = true
	if ios_runtime.swift_merge_error_metadata_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swift_merge_error_metadata_arena), usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire Swift _MergeError metadata')
	}
	ios_runtime.swift_merge_error_metadata_arena = 0
}

fn swift_merge_error_metadata_symbol(symbol string) ?u64 {
	if symbol !in ['_$ss11_MergeErrorON', '_$ss11_MergeErrorOMn', '_$ss11_MergeErrorOMa',
		'_$ss11_MergeErrorOs0B0sWP', '_$ss11_MergeErrorOs0B0sMc']! {
		return none
	}
	base := swift_merge_error_metadata_arena_checked() or { return none }
	return match symbol {
		'_$ss11_MergeErrorOMa' { base }
		'_$ss11_MergeErrorOMn' { base + u64(C.getpagesize()) + 192 }
		'_$ss11_MergeErrorOs0B0sWP' { base + u64(C.getpagesize()) + 320 }
		'_$ss11_MergeErrorOs0B0sMc' { base + u64(C.getpagesize()) + 288 }
		else { base + u64(C.getpagesize()) + 16 }
	}
}
