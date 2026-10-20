// SPDX-License-Identifier: GPL-2.0-or-later
module main

type SwiftArrayEncodingCall = fn (u64, u64, u64, u64, u64, u64, u64, u64) u64

// The conditional argument is borrowed data, not code. A cache hit never
// reads the argument array again, matching swift_getWitnessTable on native.
fn swift_array_encoding_table_checked(metadata u64, arguments u64) !u64 {
	swift_array_sequence_element_checked(metadata, false)!
	swift_array_encoding_arena()
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if table := ios_runtime.swift_array_encoding[metadata] { return table }
	if arguments == 0 || arguments & 7 != 0 || arguments > ~u64(0) - 8 {
		return swift_sequence_failure()
	}
	element_table := read64(arguments)
	if element_table == 0 || element_table & 7 != 0 { return swift_sequence_failure() }
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { return swift_sequence_failure() }
	base := u64(allocation)
	unsafe {
		*(&u64(base)) = element_table
		*(&u64(base + 8)) = ios_runtime.swift_array_encoding_descriptor
		*(&u64(base + 16)) = ios_runtime.swift_array_encoding_arena
	}
	if C.mprotect(allocation, page, C.PROT_READ) != 0 {
		C.munmap(allocation, page)
		return swift_sequence_failure()
	}
	ios_runtime.swift_array_encoding[metadata] = base + 8
	return base + 8
}

fn swift_array_encoding_checked(encoder u64, metadata u64, table u64, receiver u64, incoming u64) !u64 {
	view := swift_array_sequence_view_checked(metadata, receiver, false)!
	mut element_table := u64(0)
	C.ios_objc_initialize_lock()
	valid := (ios_runtime.swift_array_encoding[metadata] or { u64(0) }) == table && table != 0
	if valid { element_table = read64(table - 8) }
	C.ios_objc_initialize_unlock()
	if !valid { return swift_sequence_failure() }
	element := swift_sequence_value_checked(view.storage.element)!
	encoder_value := swift_raw_encoding_value_checked(encoder)!
	encoder_self := swift_raw_encoding_project_checked(encoder, encoder_value, false)!
	getter := swift_raw_encoding_callback_checked(encoder_value.table, 32)!
	container := u64(C.__builtin_alloca(48))
	get := unsafe { SwiftRawGetterCall(voidptr(swift_hash_entry(960))) }
	get(getter, container, encoder_value.metadata, encoder_value.table, encoder_self)
	container_value := swift_raw_encoding_value_checked(container)!
	defer { swift_raw_encoding_destroy(container, container_value) }
	// Even empty arrays create and destroy an owned unkeyed container. They
	// do not mutate it, so no uniqueness or encode witness is needed here.
	if view.count == 0 { return incoming }
	container_self := swift_raw_encoding_project_checked(container, container_value, true)!
	encode := swift_raw_encoding_callback_checked(container_value.table, 160)!
	storage := u64(C.__builtin_alloca(usize(element.size + element.alignment + 16)))
	temporary := (storage + element.alignment - 1) & ~(element.alignment - 1)
	copy_value := unsafe { SwiftSequenceCopy(voidptr(element.copy)) }
	destroy := unsafe { SwiftSequenceDestroy(voidptr(element.destroy)) }
	call := unsafe { SwiftArrayEncodingCall(voidptr(ios_runtime.swift_array_encoding_arena + 64)) }
	for index in u64(0) .. view.count {
		copy_value(temporary, view.owner + view.storage.tail + index * view.storage.stride, element.metadata)
		thrown := call(encode, temporary, element.metadata, element_table, container_value.metadata,
			container_value.table, container_self, incoming)
		destroy(temporary, element.metadata)
		if thrown != 0 { return thrown }
	}
	return 0
}

fn swift_array_encoding(encoder u64, metadata u64, table u64, receiver u64, incoming u64) u64 {
	return swift_array_encoding_checked(encoder, metadata, table, receiver, incoming) or { panic(err) }
}

fn swift_array_encoding_arena() u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		panic('iOS: Array encoding outside runtime lifetime')
	}
	nominal := swift_array_arena() + u64(C.getpagesize()) + 160
	protocol := swift_foundation_arena() + u64(C.getpagesize()) + 640
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_array_encoding_arena != 0 { return ios_runtime.swift_array_encoding_arena }
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } {
		panic('iOS: cannot allocate Array Encodable records')
	}
	base := u64(allocation)
	data := base + u64(page)
	// Swift encode(to:): Encoder x0, Array metadata x1, table x2, Self x20.
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e3, 0xaa1503e4, 0x580000b0, 0xd63f0200, 0xaa0003f5,
		0xa8c17bfd, 0xd65f03c0]! {
		write32(base + u64(i * 4), op)
	}
	unsafe { *(&u64(base + 32)) = u64(voidptr(swift_array_encoding)) }
	// Generic UnkeyedEncodingContainer.encode<T>: value, T metadata, T:Encodable,
	// container metadata/table in x0..x4, mutable container Self in x20, x21 error.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e0, 0xaa0203e1,
		0xaa0303e2, 0xaa0403e3, 0xaa0503e4, 0xaa0603f4, 0xaa0703f5, 0xd63f0200, 0xaa1503e0, 0xa9425bf5,
		0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(base + 64 + u64(i * 4), op)
	}
	swift_protocol_relative(data, protocol)
	swift_protocol_relative(data + 4, nominal)
	swift_protocol_relative(data + 8, data + 64)
	write32(data + 12, 0x20100) // One conditional Element:Encodable requirement.
	write32(data + 16, 0x80)
	swift_protocol_relative(data + 20, data + 48)
	swift_protocol_relative(data + 24, protocol)
	write32(data + 28, 0x30002) // Two pattern words, one private word, generic.
	swift_protocol_relative(data + 36, base + u64(page * 2))
	C.memcpy(voidptr(data + 48), c'x', 2)
	unsafe {
		*(&u64(data + 64)) = data
		*(&u64(data + 72)) = base
	}
	C.__builtin___clear_cache(allocation, voidptr(base + 136))
	if C.mprotect(allocation, page, C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), page, C.PROT_READ) != 0 {
		C.munmap(allocation, page * 3)
		panic('iOS: cannot seal Array Encodable records')
	}
	ios_runtime.swift_array_encoding_arena = base
	ios_runtime.swift_array_encoding_descriptor = data
	return base
}

fn swift_array_encoding_symbol(symbol string) ?u64 {
	if symbol != '_$sSayxGSEsSERzlMc' || ios_runtime == unsafe { nil }
		|| ios_runtime.swift_concurrency_retired {
		return none
	}
	return swift_array_encoding_arena() + u64(C.getpagesize())
}

fn swift_array_encoding_stop() {
	page := usize(C.getpagesize())
	for _, table in ios_runtime.swift_array_encoding {
		if C.munmap(voidptr(table - 8), page) != 0 {
			panic('iOS: cannot retire Array Encodable table')
		}
	}
	unsafe { ios_runtime.swift_array_encoding.free() }
	if ios_runtime.swift_array_encoding_arena != 0 {
		if C.munmap(voidptr(ios_runtime.swift_array_encoding_arena), page * 3) != 0 {
			panic('iOS: cannot retire Array Encodable records')
		}
		ios_runtime.swift_array_encoding_arena = 0
	}
}
