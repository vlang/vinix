// SPDX-License-Identifier: GPL-2.0-or-later
module main

// TaskPriority's measured value is a POD byte. These value witnesses use the
// ordinary ARM64 ABI and do not retain either value or its borrowed metadata.
fn swift_task_priority_copy(destination u64, source u64, metadata u64) u64 {
	unsafe { *(&u8(destination)) = *(&u8(source)) }
	return destination
}
fn swift_task_priority_destroy(value u64, metadata u64) {}

// The native single-payload witnesses choose tag widths from a wrapping
// UInt32 addition. Load/store individual bytes so unaligned values and exact
// protected boundaries work without reading beyond the measured storage.
fn swift_task_priority_tag_bytes(empty_cases u32) u32 {
	if empty_cases == 0 { return 0 }
	bits := empty_cases + u32(255)
	return if bits >> 8 < 255 { u32(1) } else if bits < 0x00ffff00 { u32(2) } else { u32(4) }
}
fn swift_task_priority_enum_get(value u64, empty_cases u32, metadata u64) u32 {
	if empty_cases == 0 { return 0 }
	mut tag := u32(0)
	for i in u32(0) .. swift_task_priority_tag_bytes(empty_cases) {
		tag |= u32(unsafe { *(&u8(value + 1 + u64(i))) }) << (i * 8)
	}
	if tag == 0 { return 0 }
	return ((tag << 8) | u32(unsafe { *(&u8(value)) })) - u32(255)
}
fn swift_task_priority_enum_store(value u64, which_case u32, empty_cases u32, metadata u64) {
	mut tag := u32(0)
	if which_case != 0 {
		payload := which_case - 1
		unsafe { *(&u8(value)) = u8(payload) }
		tag = (payload >> 8) + 1
	}
	for i in u32(0) .. swift_task_priority_tag_bytes(empty_cases) {
		unsafe { *(&u8(value + 1 + u64(i))) = u8(tag >> (i * 8)) }
	}
}

fn swift_task_priority_arena() !u64 {
	$if !arm64 { return error('iOS: TaskPriority metadata requires ARM64') }
	if ios_runtime == unsafe { nil } { return error('iOS: TaskPriority metadata outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_concurrency_retired { return error('iOS: TaskPriority metadata outside runtime lifetime') }
	if ios_runtime.swift_task_priority_arena != 0 { return ios_runtime.swift_task_priority_arena }
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == unsafe { voidptr(-1) } { return error('iOS: cannot allocate TaskPriority metadata') }
	base := u64(arena)
	data := base + page
	metadata := data + 16
	witness := data + 64
	descriptor := data + 160
	module_descriptor := data + 192
	write32(base, 0x58000080) // ldr x0,literal metadata pointer at +16
	write32(base + 4, 0xd2800001) // MetadataResponse state: Complete.
	write32(base + 8, 0xd65f03c0)
	unsafe {
		*(&u64(base + 16)) = metadata
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x200
		*(&u64(metadata + 8)) = descriptor
	}
	for i, function in [u64(unsafe { voidptr(swift_task_priority_copy) }),
		u64(unsafe { voidptr(swift_task_priority_destroy) }), u64(unsafe { voidptr(swift_task_priority_copy) }),
		u64(unsafe { voidptr(swift_task_priority_copy) }), u64(unsafe { voidptr(swift_task_priority_copy) }),
		u64(unsafe { voidptr(swift_task_priority_copy) }), u64(unsafe { voidptr(swift_task_priority_enum_get) }),
		u64(unsafe { voidptr(swift_task_priority_enum_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = function }
	}
	unsafe { *(&u64(witness + 64)) = 1; *(&u64(witness + 72)) = 1 }
	write32(witness + 80, 0x02000000) // POD, inline, alignment 1, addressable for dependencies; no extra inhabitants.
	write32(descriptor, 0x51)
	swift_protocol_relative(descriptor + 4, module_descriptor)
	swift_protocol_relative(descriptor + 8, data + 216)
	swift_protocol_relative(descriptor + 12, base)
	// One field at offset zero; the vector starts at metadata word two.
	// Reflection records are omitted, as in the existing primitive metadata.
	write32(descriptor + 20, 1)
	write32(descriptor + 24, 2)
	swift_protocol_relative(module_descriptor + 8, data + 208)
	C.memcpy(unsafe { voidptr(data + 208) }, c'Swift', 6)
	C.memcpy(unsafe { voidptr(data + 216) }, c'TaskPriority', 13)
	C.__builtin___clear_cache(arena, unsafe { voidptr(base + 24) })
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(unsafe { voidptr(data) }, usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page * 2)) != 0 { panic('iOS: cannot retire unsealed TaskPriority metadata') }
		return error('iOS: cannot seal TaskPriority metadata')
	}
	ios_runtime.swift_task_priority_arena = base
	return base
}

fn swift_task_priority_metadata() u64 {
	base := swift_task_priority_arena() or { panic(err) }
	return base + u64(C.getpagesize()) + 16
}

fn swift_task_priority_stop() {
	// Called under the runtime lock after every metadata user has drained.
	if ios_runtime.swift_task_priority_arena == 0 { return }
	if C.munmap(unsafe { voidptr(ios_runtime.swift_task_priority_arena) }, usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire TaskPriority metadata')
	}
	ios_runtime.swift_task_priority_arena = 0
}
