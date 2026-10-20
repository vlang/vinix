// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftBoolMetadataFailure {}

fn (_ &SwiftBoolMetadataFailure) msg() string {
	return 'iOS: Swift Bool metadata requires an active runtime and sealed storage'
}

fn (_ &SwiftBoolMetadataFailure) code() int { return 1 }

__global swift_bool_metadata_failure_value = SwiftBoolMetadataFailure{}

fn swift_bool_metadata_failure() IError { return unsafe { &swift_bool_metadata_failure_value } }

// Bool has its own canonical nominal metadata and value-witness table. Its
// one-byte POD operations and 254 extra inhabitants match the measured
// ObjCBool operations, without sharing either type's metadata identity.
fn swift_bool_metadata_arena_checked() !u64 {
	$if !arm64 {
		return swift_bool_metadata_failure()
	}
	if ios_runtime == unsafe { nil } { return swift_bool_metadata_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_bool_metadata_retired || ios_runtime.swift_concurrency_retired {
		return swift_bool_metadata_failure()
	}
	if ios_runtime.swift_bool_metadata_arena != 0 { return ios_runtime.swift_bool_metadata_arena }
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == unsafe { voidptr(-1) } { return swift_bool_metadata_failure() }
	base := u64(arena)
	data := base + page
	metadata := data + 16
	witness := data + 64
	descriptor := data + 160
	module_descriptor := data + 192
	write32(base, 0x58000080)
	write32(base + 4, 0xd2800001)
	write32(base + 8, 0xd65f03c0)
	write32(base + 12, 0xd503201f)
	unsafe {
		*(&u64(base + 16)) = metadata
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x200
		*(&u64(metadata + 8)) = descriptor
	}
	for i, function in [u64(unsafe { voidptr(swift_byte_copy) }),
		u64(unsafe { voidptr(swift_integer_destroy) }), u64(unsafe { voidptr(swift_byte_copy) }),
		u64(unsafe { voidptr(swift_byte_copy) }), u64(unsafe { voidptr(swift_byte_copy) }),
		u64(unsafe { voidptr(swift_byte_copy) }), u64(unsafe { voidptr(swift_objc_bool_enum_get) }),
		u64(unsafe { voidptr(swift_objc_bool_enum_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = function }
	}
	unsafe {
		*(&u64(witness + 64)) = 1
		*(&u64(witness + 72)) = 1
	}
	write32(witness + 84, 254) // POD, alignment1, inline; 254 extra inhabitants.
	write32(descriptor, 0x51) // Unique nongeneric struct; no reflection/initialization extensions.
	swift_protocol_relative(descriptor + 4, module_descriptor)
	swift_protocol_relative(descriptor + 8, data + 224)
	swift_protocol_relative(descriptor + 12, base)
	write32(descriptor + 20, 1)
	write32(descriptor + 24, 2)
	swift_protocol_relative(module_descriptor + 8, data + 208)
	C.memcpy(voidptr(data + 208), c'Swift', 6)
	C.memcpy(voidptr(data + 224), c'Bool', 5)
	C.__builtin___clear_cache(arena, voidptr(base + 24))
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page * 2)) != 0 {
			panic('iOS: cannot retire unsealed Swift Bool metadata')
		}
		return swift_bool_metadata_failure()
	}
	ios_runtime.swift_bool_metadata_arena = base
	return base
}

fn swift_bool_metadata_stop() {
	// Runtime lock held after metadata users and callbacks have drained.
	ios_runtime.swift_bool_metadata_retired = true
	if ios_runtime.swift_bool_metadata_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swift_bool_metadata_arena), usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire Swift Bool metadata')
	}
	ios_runtime.swift_bool_metadata_arena = 0
}

fn swift_bool_metadata_symbol(symbol string) ?u64 {
	if symbol !in ['_$sSbN', '_$sSbMn', '_$sSbMa']! { return none }
	base := swift_bool_metadata_arena_checked() or { return none }
	return match symbol {
		'_$sSbMa' { base }
		'_$sSbMn' { base + u64(C.getpagesize()) + 160 }
		else { base + u64(C.getpagesize()) + 16 }
	}
}
