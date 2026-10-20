// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftStaticStringMetadataFailure {}

fn (_ &SwiftStaticStringMetadataFailure) msg() string {
	return 'iOS: Swift StaticString metadata requires an active runtime and sealed storage'
}

fn (_ &SwiftStaticStringMetadataFailure) code() int { return 1 }

__global swift_static_string_metadata_failure_value = SwiftStaticStringMetadataFailure{}

fn swift_static_string_metadata_failure() IError {
	return unsafe { &swift_static_string_metadata_failure_value }
}

// Frozen Builtin.Word, Builtin.Word, Builtin.Int8: 17 initialized bytes,
// stride 24, alignment 8, POD and inline in the three-word value buffer.
// The data word may be a Unicode scalar or an inaccessible borrowed pointer.
// Value operations copy the representation without inspecting its contents.
fn swift_static_string_copy(destination u64, source u64, _metadata u64) u64 {
	C.memmove(voidptr(destination), voidptr(source), 17)
	return destination
}

// Builtin fields have no extra inhabitants. Every enclosing single-payload
// enum uses one external tag byte when it has empty cases: the 17-byte payload
// can encode all UInt32 empty-case indices in its first four bytes.
fn swift_static_string_enum_get(value u64, cases u32, _metadata u64) u32 {
	if cases == 0 || unsafe { *(&u8(value + 17)) } == 0 { return 0 }
	mut tag := u32(0)
	for i in 0 .. 4 { tag |= u32(unsafe { *(&u8(value + u64(i))) }) << (i * 8) }
	return tag + u32(1)
}

fn swift_static_string_enum_store(value u64, tag u32, cases u32, _metadata u64) {
	if tag != 0 {
		C.memset(voidptr(value), 0, 17)
		for i in 0 .. 4 {
			unsafe { *(&u8(value + u64(i))) = u8((tag - 1) >> (i * 8)) }
		}
	}
	if cases != 0 { unsafe { *(&u8(value + 17)) = u8(tag != 0) } }
}

fn swift_static_string_metadata_arena_checked() !u64 {
	$if !arm64 {
		return swift_static_string_metadata_failure()
	}
	if ios_runtime == unsafe { nil } { return swift_static_string_metadata_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_static_string_metadata_retired || ios_runtime.swift_concurrency_retired {
		return swift_static_string_metadata_failure()
	}
	if ios_runtime.swift_static_string_metadata_arena != 0 {
		return ios_runtime.swift_static_string_metadata_arena
	}
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == voidptr(-1) { return swift_static_string_metadata_failure() }
	base := u64(arena)
	data := base + page
	metadata := data + 16
	witness := data + 64
	descriptor := data + 160
	module_descriptor := data + 192
	// MetadataResponse: canonical metadata in x0, complete state in x1.
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
	write32(metadata + 20, 8)
	write32(metadata + 24, 16)
	for i, function in [u64(unsafe { voidptr(swift_static_string_copy) }),
		u64(unsafe { voidptr(swift_integer_destroy) }),
		u64(unsafe { voidptr(swift_static_string_copy) }),
		u64(unsafe { voidptr(swift_static_string_copy) }),
		u64(unsafe { voidptr(swift_static_string_copy) }),
		u64(unsafe { voidptr(swift_static_string_copy) }),
		u64(unsafe { voidptr(swift_static_string_enum_get) }),
		u64(unsafe { voidptr(swift_static_string_enum_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = function }
	}
	unsafe {
		*(&u64(witness + 64)) = 17
		*(&u64(witness + 72)) = 24
	}
	write32(witness + 80, 7)
	write32(descriptor, 0x51)
	swift_protocol_relative(descriptor + 4, module_descriptor)
	swift_protocol_relative(descriptor + 8, data + 224)
	swift_protocol_relative(descriptor + 12, base)
	write32(descriptor + 20, 3)
	write32(descriptor + 24, 2)
	swift_protocol_relative(module_descriptor + 8, data + 208)
	C.memcpy(voidptr(data + 208), c'Swift', 6)
	C.memcpy(voidptr(data + 224), c'StaticString', 13)
	C.__builtin___clear_cache(arena, voidptr(base + 24))
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page * 2)) != 0 {
			panic('iOS: cannot retire unsealed Swift StaticString metadata')
		}
		return swift_static_string_metadata_failure()
	}
	ios_runtime.swift_static_string_metadata_arena = base
	return base
}

fn swift_static_string_metadata_stop() {
	// Runtime lock held after Optional/Array users and callbacks drain.
	ios_runtime.swift_static_string_metadata_retired = true
	if ios_runtime.swift_static_string_metadata_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swift_static_string_metadata_arena), usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire Swift StaticString metadata')
	}
	ios_runtime.swift_static_string_metadata_arena = 0
}

fn swift_static_string_metadata_symbol(symbol string) ?u64 {
	if symbol !in ['_$ss12StaticStringVN', '_$ss12StaticStringVMn', '_$ss12StaticStringVMa']! {
		return none
	}
	base := swift_static_string_metadata_arena_checked() or { return none }
	return match symbol {
		'_$ss12StaticStringVMa' { base }
		'_$ss12StaticStringVMn' { base + u64(C.getpagesize()) + 160 }
		else { base + u64(C.getpagesize()) + 16 }
	}
}
