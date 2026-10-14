// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftObjcBoolMetadataFailure {}
fn (_ &SwiftObjcBoolMetadataFailure) msg() string { return 'iOS: ObjCBool metadata requires an active runtime and sealed storage' }
fn (_ &SwiftObjcBoolMetadataFailure) code() int { return 1 }
__global swift_objc_bool_metadata_failure_value = SwiftObjcBoolMetadataFailure{}
fn swift_objc_bool_metadata_failure() IError { return unsafe { &swift_objc_bool_metadata_failure_value } }

// ARM64 ObjCBool has valid payloads 0/1 and 254 extra inhabitants. Preserve
// the native UInt32 count+1 wrap and unaligned little-endian tag storage.
fn swift_objc_bool_tag_width(empty_cases u32) u32 {
	if empty_cases < 255 { return 0 }
	rounded := empty_cases + u32(1)
	if rounded >> 8 < 255 { return 1 }
	return if rounded < 0x00ffff00 { u32(2) } else { u32(4) }
}
fn swift_objc_bool_enum_get(value u64, empty_cases u32, _metadata u64) u32 {
	if empty_cases == 0 { return 0 }
	mut tag := u32(0)
	for i in u32(0) .. swift_objc_bool_tag_width(empty_cases) {
		tag |= u32(unsafe { *(&u8(value + 1 + i)) }) << (i * 8)
	}
	payload := u32(unsafe { *(&u8(value)) })
	if tag != 0 { return (tag << 8 | payload) - u32(1) }
	return if payload < 2 { u32(0) } else { payload - u32(1) }
}
fn swift_objc_bool_enum_store(value u64, which_case u32, empty_cases u32, _metadata u64) {
	mut tag := u32(0)
	if which_case > 254 {
		bits := which_case - u32(255)
		unsafe { *(&u8(value)) = u8(bits) }
		tag = (bits >> 8) + u32(1)
	} else if which_case != 0 {
		unsafe { *(&u8(value)) = u8(which_case + u32(1)) }
	}
	for i in u32(0) .. swift_objc_bool_tag_width(empty_cases) {
		unsafe { *(&u8(value + 1 + i)) = u8(tag >> (i * 8)) }
	}
}

fn swift_objc_bool_arena_checked() !u64 {
	$if !arm64 { return swift_objc_bool_metadata_failure() }
	if ios_runtime == unsafe { nil } { return swift_objc_bool_metadata_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_objc_bool_retired { return swift_objc_bool_metadata_failure() }
	if ios_runtime.swift_objc_bool_arena != 0 { return ios_runtime.swift_objc_bool_arena }
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == unsafe { voidptr(-1) } { return swift_objc_bool_metadata_failure() }
	base := u64(arena); data := base + page
	metadata := data + 16; witness := data + 64
	descriptor := data + 160; module_descriptor := data + 192
	write32(base, 0x58000080); write32(base + 4, 0xd2800001)
	write32(base + 8, 0xd65f03c0); write32(base + 12, 0xd503201f)
	unsafe {
		*(&u64(base + 16)) = metadata
		*(&u64(metadata - 8)) = witness; *(&u64(metadata)) = 0x200
		*(&u64(metadata + 8)) = descriptor
	}
	for i, function in [u64(unsafe { voidptr(swift_byte_copy) }),
		u64(unsafe { voidptr(swift_integer_destroy) }), u64(unsafe { voidptr(swift_byte_copy) }),
		u64(unsafe { voidptr(swift_byte_copy) }), u64(unsafe { voidptr(swift_byte_copy) }),
		u64(unsafe { voidptr(swift_byte_copy) }), u64(unsafe { voidptr(swift_objc_bool_enum_get) }),
		u64(unsafe { voidptr(swift_objc_bool_enum_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = function }
	}
	unsafe { *(&u64(witness + 64)) = 1; *(&u64(witness + 72)) = 1 }
	write32(witness + 84, 254) // POD, alignment1, inline; 254 extra inhabitants.
	write32(descriptor, 0x51) // Unique nongeneric struct; no reflection/initialization extensions.
	swift_protocol_relative(descriptor + 4, module_descriptor)
	swift_protocol_relative(descriptor + 8, data + 224)
	swift_protocol_relative(descriptor + 12, base)
	write32(descriptor + 20, 1); write32(descriptor + 24, 2)
	swift_protocol_relative(module_descriptor + 8, data + 208)
	C.memcpy(voidptr(data + 208), c'ObjectiveC', 11)
	C.memcpy(voidptr(data + 224), c'ObjCBool', 9)
	C.__builtin___clear_cache(arena, voidptr(base + 24))
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page * 2)) != 0 { panic('iOS: cannot retire unsealed ObjCBool metadata') }
		return swift_objc_bool_metadata_failure()
	}
	ios_runtime.swift_objc_bool_arena = base
	return base
}
fn swift_objc_bool_metadata_stop() {
	// Runtime lock held after metadata users and callbacks have drained.
	ios_runtime.swift_objc_bool_retired = true
	if ios_runtime.swift_objc_bool_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swift_objc_bool_arena), usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire ObjCBool metadata')
	}
	ios_runtime.swift_objc_bool_arena = 0
}
