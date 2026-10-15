// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn swift_calendar_input_checked(value u64) !u8 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return error('iOS: Swift Calendar construction outside runtime lifetime')
	}
	if value == 0 { return error('iOS: Swift Calendar requires an Identifier value') }
	identifier := unsafe { *(&u8(value)) }
	if identifier >= 27 { return error('iOS: invalid Swift Calendar Identifier') }
	return identifier
}

fn swift_calendar_initialize(identifier u64, output u64) {
	which := swift_calendar_input_checked(identifier) or { panic(err) }
	data := swift_foundation_arena() + u64(C.getpagesize())
	owner := swift_heap_allocate(data + 1808, 24, 7)
	// The consuming Identifier is POD: only its one readable byte is needed.
	// This owner stores a complete independent snapshot and has no cache retain.
	unsafe {
		*(&u64(owner + 16)) = u64(which)
		*(&SwiftURLWords(output)) = SwiftURLWords{owner: owner, table: data + 2048}
	}
}

fn swift_calendar_storage_destroy(owner u64) {
	swift_heap_deallocate(owner, 24, 7)
}

fn swift_calendar_identifier_checked(owner u64) !u8 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return error('iOS: Swift Calendar outside runtime lifetime')
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	storage := ios_runtime.swift_heap[owner] or { return error('iOS: Swift Calendar requires registered storage') }
	if storage.deiniting || storage.size != 24 || storage.mask != 7
		|| ios_runtime.swift_foundation_arena == 0
		|| storage.metadata != ios_runtime.swift_foundation_arena + u64(C.getpagesize()) + 1808
		|| read64(owner) != storage.metadata || read64(owner + 16) >= 27 {
		return error('iOS: unsupported Swift Calendar storage')
	}
	return u8(read64(owner + 16))
}

fn swift_calendar_identifier(owner u64, output u64) {
	which := swift_calendar_identifier_checked(owner) or { panic(err) }
	unsafe { *(&u8(output)) = which }
}

fn swift_calendar_emit(code u64, data u64) {
	// Consuming indirect Identifier in x0; owned two-word result through x8.
	write32(code + 2368, 0xaa0803e1)
	write32(code + 2372, 0x58000070)
	write32(code + 2376, 0xd61f0200)
	unsafe { *(&u64(code + 2384)) = u64(voidptr(swift_calendar_initialize)) }
	// Borrow Self, obtain the implementation's formal type, and invoke its
	// Identifier getter at +24. Forward the original one-byte result in x8.
	for i, op in [u32(0xa9bd57f6), 0xa9014ff4, 0xa9027bfd, 0x910083fd,
		0xaa0803f3, 0xa9405a95, 0xaa1503e0, 0x580002b0, 0xd63f0200,
		0xaa1603e9, 0xf8418d2a, 0xaa1303e8, 0xaa1503f4, 0xaa1603e1,
		0xd63f0140, 0xa9427bfd, 0xa9414ff4, 0xa8c357f6, 0xd65f03c0]! {
		write32(code + 2400 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 2512)) = u64(voidptr(swift_object_type)) }
	entry := code + 2528
	metadata := data + 1896
	descriptor := data + 1600 // Canonical parent of Calendar.Identifier.
	witness := data + 1936
	write32(entry, 0x58000080); write32(entry + 4, 0xd2800001); write32(entry + 8, 0xd65f03c0)
	unsafe {
		*(&u64(entry + 16)) = metadata
		*(&u64(metadata - 8)) = witness; *(&u64(metadata)) = 0x200; *(&u64(metadata + 8)) = descriptor
		*(&u64(witness + 64)) = 16; *(&u64(witness + 72)) = 16
	}
	swift_protocol_relative(descriptor + 12, entry)
	write32(descriptor + 20, 1); write32(descriptor + 24, 2)
	for i, target in [u64(unsafe { voidptr(swift_url_copy) }), u64(unsafe { voidptr(swift_url_destroy) }),
		u64(unsafe { voidptr(swift_url_copy) }), u64(unsafe { voidptr(swift_url_assign_copy) }),
		u64(unsafe { voidptr(swift_url_take) }), u64(unsafe { voidptr(swift_url_assign_take) }),
		u64(unsafe { voidptr(swift_url_enum_get) }), u64(unsafe { voidptr(swift_url_enum_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = target }
	}
	write32(witness + 80, 0x02010007); write32(witness + 84, 0x7fffffff)
	// Private native Swift class metadata supports ordinary heap ARC and formal
	// object-type dispatch. No Objective-C class or reflection API is exposed.
	write32(code + 2560, 0xaa1403e0); write32(code + 2564, 0x58000070); write32(code + 2568, 0xd61f0200)
	unsafe {
		*(&u64(code + 2576)) = u64(voidptr(swift_calendar_storage_destroy))
		*(&u64(data + 1792)) = code + 2560
		*(&u64(data + 1840)) = 2
		*(&u64(data + 1872)) = data + 2560
		*(&u64(data + 2072)) = code + 2592
	}
	write32(data + 1848, 2) // Class flags: native Swift reference counting.
	write32(data + 1856, 24); write32(data + 1860, 7)
	write32(data + 1864, 96); write32(data + 1868, 16)
	write32(data + 2560, 0x50)
	swift_protocol_relative(data + 2564, data + 64)
	swift_protocol_relative(data + 2568, data + 2624)
	C.memcpy(voidptr(data + 2624), c'CalendarStorage', 16)
	write32(code + 2592, 0xaa1403e0); write32(code + 2596, 0xaa0803e1)
	write32(code + 2600, 0x58000050); write32(code + 2604, 0xd61f0200)
	unsafe { *(&u64(code + 2608)) = u64(voidptr(swift_calendar_identifier)) }
}
