// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Array's frozen payload is one BridgeObject. Its witnesses do not inspect
// Element or the storage class. Storage ARC accepts registered UTF-8 buffers,
// typed value-element tails, ObjC owners and immortal references.
fn swift_array_copy(destination u64, source u64, _metadata u64) u64 {
	owner := read64(source)
	swift_bridge_retain(owner)
	unsafe { *(&u64(destination)) = owner }
	return destination
}
fn swift_array_destroy(value u64, _metadata u64) { swift_bridge_release(read64(value)) }
fn swift_array_assign_copy(destination u64, source u64, _metadata u64) u64 {
	owner := read64(source)
	swift_bridge_retain(owner)
	previous := read64(destination)
	unsafe { *(&u64(destination)) = owner }
	swift_bridge_release(previous)
	return destination
}
fn swift_array_take(destination u64, source u64, _metadata u64) u64 {
	unsafe { *(&u64(destination)) = read64(source) }
	return destination
}
fn swift_array_assign_take(destination u64, source u64, _metadata u64) u64 {
	previous := read64(destination)
	unsafe { *(&u64(destination)) = read64(source) }
	swift_bridge_release(previous)
	return destination
}
fn swift_array_enum_get(value u64, empty_cases u32, _metadata u64) u32 {
	if empty_cases > 0x7fffffff && unsafe { *(&u8(value + 8)) } != 0 {
		return unsafe { *(&u32(value)) } + 0x80000000
	}
	owner := read64(value)
	return if owner >> 32 == 0 { u32(owner) + 1 } else { u32(0) }
}
fn swift_array_enum_store(value u64, which_case u32, empty_cases u32, _metadata u64) {
	if empty_cases > 0x7fffffff {
		unsafe { *(&u8(value + 8)) = if which_case > 0x7fffffff { u8(1) } else { u8(0) } }
	}
	if which_case != 0 {
		unsafe { *(&u64(value)) = if which_case <= 0x7fffffff { u64(which_case - 1) } else { u64(which_case - 0x80000000) } }
	}
}

// Every specialization is complete without completing Element: the layout
// and ownership operations are independent of its size and witnesses.
// Canonical metadata is keyed by the exact Element pointer, never its name.
fn swift_array_access(_request u64, element u64) SwiftAssociatedMetadata {
	if element == 0 { panic('iOS: Array metadata requires Element metadata') }
	swift_array_arena()
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if metadata := ios_runtime.swift_array_metadata[element] {
		return SwiftAssociatedMetadata{ metadata: metadata }
	}
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { panic('iOS: cannot allocate Swift Array metadata') }
	base := u64(allocation)
	data := ios_runtime.swift_array_arena + u64(page)
	metadata := base + 8
	unsafe {
		*(&u64(base)) = data + 64
		*(&u64(metadata)) = 0x200
		*(&u64(metadata + 8)) = data + 160
		*(&u64(metadata + 16)) = element
		// The field offset (_buffer) is zero, at metadata word 3.
	}
	if C.mprotect(allocation, page, C.PROT_READ) != 0 {
		C.munmap(allocation, page)
		panic('iOS: cannot seal Swift Array metadata')
	}
	ios_runtime.swift_array_metadata[element] = metadata
	return SwiftAssociatedMetadata{ metadata: metadata }
}

fn swift_array_instantiate(descriptor u64, arguments u64, pattern u64) u64 {
	data := swift_array_arena() + u64(C.getpagesize())
	if descriptor != data + 160 || pattern != data + 272 || arguments == 0 {
		panic('iOS: invalid Swift Array metadata instantiation')
	}
	return swift_array_access(0, read64(arguments)).metadata
}

fn swift_array_arena() u64 {
	$if !arm64 { panic('iOS: Swift Array metadata accessor requires ARM64') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_array_arena != 0 { return ios_runtime.swift_array_arena }
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 3), C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == unsafe { voidptr(-1) } { panic('iOS: cannot allocate Swift Array descriptor') }
	base := u64(arena)
	data := base + page
	descriptor := data + 160
	// Ordinary ARM64 metadata response uses x0/x1. Relative descriptor and
	// instantiation-pattern pointers target these nearby tail-call bridges.
	for offset, target in [u64(unsafe { voidptr(swift_array_access) }), u64(unsafe { voidptr(swift_array_instantiate) })]! {
		address := base + u64(offset * 32)
		write32(address, 0x58000050) // ldr x16,literal +8
		write32(address + 4, 0xd61f0200) // br x16
		unsafe { *(&u64(address + 8)) = target }
	}
	for i, function in [u64(unsafe { voidptr(swift_array_copy) }),
		u64(unsafe { voidptr(swift_array_destroy) }), u64(unsafe { voidptr(swift_array_copy) }),
		u64(unsafe { voidptr(swift_array_assign_copy) }), u64(unsafe { voidptr(swift_array_take) }),
		u64(unsafe { voidptr(swift_array_assign_take) }), u64(unsafe { voidptr(swift_array_enum_get) }),
		u64(unsafe { voidptr(swift_array_enum_store) })]! {
		unsafe { *(&u64(data + 64 + u64(i * 8))) = function }
	}
	unsafe { *(&u64(data + 128)) = 8; *(&u64(data + 136)) = 8 }
	write32(data + 144, 0x00010007) // Non-POD, inline, 8-byte alignment; bitwise-takable.
	write32(data + 148, 0x7fffffff)
	write32(descriptor, 0xd1) // Unique generic struct, no prespecialization records.
	swift_protocol_relative(descriptor + 4, data + 224)
	swift_protocol_relative(descriptor + 8, data + 248)
	swift_protocol_relative(descriptor + 12, base)
	// No reflection Fields record. One field, offset vector at word 3.
	write32(descriptor + 20, 1)
	write32(descriptor + 24, 3)
	// Generic context: one key type parameter, no requirements. Cache storage
	// remains writable and zero-filled; descriptor and witnesses are read-only.
	swift_protocol_relative(descriptor + 28, base + page * 2)
	swift_protocol_relative(descriptor + 32, data + 272)
	write32(descriptor + 36, 1)
	write32(descriptor + 40, 1)
	write32(descriptor + 44, 0x80)
	swift_protocol_relative(data + 232, data + 240)
	C.memcpy(unsafe { voidptr(data + 240) }, c'Swift', 6)
	C.memcpy(unsafe { voidptr(data + 248) }, c'Array', 6)
	swift_protocol_relative(data + 272, base + 32)
	write32(data + 280, 0x40000000) // Struct metadata kind, no extra/trailing patterns.
	swift_protocol_relative(data + 284, data + 64)
	swift_array_class_emit(data)
	C.__builtin___clear_cache(arena, unsafe { voidptr(base + 48) })
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(unsafe { voidptr(data) }, usize(page), C.PROT_READ) != 0 {
		C.munmap(arena, usize(page * 3))
		panic('iOS: cannot seal Swift Array descriptor')
	}
	ios_runtime.swift_array_arena = base
	return base
}

fn swift_array_symbol(symbol string) ?u64 {
	if address := swift_set_symbol(symbol) { return address }
	if address := swift_collection_symbol(symbol) { return address }
	if address := swift_array_sequence_symbol(symbol) { return address }
	return match symbol {
		// This data symbol denotes the object itself, not a pointer cell. All
		// zero-capacity factories and imported Array payloads share its identity.
		'__swiftEmptyArrayStorage' { swift_array_empty() }
		'_$ss27_allocateUninitializedArrayySayxG_BptBwlF' { u64(unsafe { voidptr(swift_array_allocate) }) }
		'_$sSa28_allocateBufferUninitialized15minimumCapacitys06_ArrayB0VyxGSi_tFZ' { u64(unsafe { voidptr(swift_array_buffer_allocate) }) }
		'_$sSaMa' { swift_array_arena() }
		'_$sSaMn' { swift_array_arena() + u64(C.getpagesize()) + 160 }
		'_$ss23_ContiguousArrayStorageCMn' { swift_array_class_descriptor() }
		else { none }
	}
}

fn swift_array_stop() {
	swift_array_encoding_stop()
	swift_set_stop()
	swift_collection_stop()
	swift_array_sequence_stop()
	// Shutdown has joined workers and drained all owners/callbacks. Retire
	// specialization pages before the witnesses/descriptors they reference.
	page := usize(C.getpagesize())
	for _, metadata in ios_runtime.swift_array_metadata {
		if C.munmap(unsafe { voidptr(metadata - 8) }, page) != 0 { panic('iOS: cannot retire Swift Array metadata') }
	}
	unsafe { ios_runtime.swift_array_metadata.free() }
	if ios_runtime.swift_array_arena != 0 {
		if C.munmap(unsafe { voidptr(ios_runtime.swift_array_arena) }, page * 3) != 0 { panic('iOS: cannot retire Swift Array descriptor') }
		ios_runtime.swift_array_arena = 0
	}
}
