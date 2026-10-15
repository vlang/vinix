// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn swift_timezone_initialize(seconds i64, output u64) {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { panic('iOS: Swift TimeZone outside runtime lifetime') }
	if seconds < -64800 || seconds > 64800 {
		unsafe { *(&u64(output)) = 0; *(&u64(output + 8)) = 0 }
		return
	}
	data := swift_foundation_arena() + u64(C.getpagesize())
	owner := swift_heap_allocate(data + 2656, 24, 7)
	unsafe {
		*(&i64(owner + 16)) = seconds
		*(&SwiftURLWords(output)) = SwiftURLWords{owner: owner, table: data + 2960}
	}
}

fn swift_timezone_seconds_checked(owner u64) !i64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return error('iOS: Swift TimeZone outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	storage := ios_runtime.swift_heap[owner] or { return error('iOS: Swift TimeZone requires registered storage') }
	if storage.deiniting || storage.size != 24 || storage.mask != 7 || ios_runtime.swift_foundation_arena == 0
		|| storage.metadata != ios_runtime.swift_foundation_arena + u64(C.getpagesize()) + 2656 || read64(owner) != storage.metadata {
		return error('iOS: unsupported Swift TimeZone storage')
	}
	seconds := unsafe { *(&i64(owner + 16)) }
	if seconds < -64800 || seconds > 64800 { return error('iOS: invalid fixed Swift TimeZone offset') }
	return seconds
}

fn swift_timezone_input_checked(value u64) !SwiftURLWords {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired || value == 0 { return error('iOS: Swift TimeZone requires a live value') }
	words := unsafe { *(&SwiftURLWords(value)) }
	if words.table != ios_runtime.swift_foundation_arena + u64(C.getpagesize()) + 2960 { return error('iOS: only fixed-offset Swift TimeZone values are implemented') }
	swift_timezone_seconds_checked(words.owner)!
	return words
}

fn swift_timezone_identifier(owner u64) SwiftStringWords {
	seconds := swift_timezone_seconds_checked(owner) or { panic(err) }
	return swift_timezone_identifier_seconds(seconds)
}

fn swift_timezone_identifier_seconds(seconds i64) SwiftStringWords {
	// The identifier rounds to minutes, while calculations preserve exact
	// seconds. Native rounds half a minute away from zero on both signs.
	minutes := ((if seconds < 0 { -seconds } else { seconds }) + 30) / 60
	if minutes == 0 { return swift_string_literal(c'GMT', 3, true) }
	buffer := u64(C.__builtin_alloca(8))
	C.memcpy(voidptr(buffer), c'GMT', 3)
	unsafe {
		*(&u8(buffer + 3)) = if seconds < 0 { `-` } else { `+` }
		*(&u8(buffer + 4)) = u8(`0` + minutes / 600)
		*(&u8(buffer + 5)) = u8(`0` + (minutes / 60) % 10)
		*(&u8(buffer + 6)) = u8(`0` + (minutes % 60) / 10)
		*(&u8(buffer + 7)) = u8(`0` + minutes % 10)
	}
	return swift_string_literal(unsafe { &u8(buffer) }, 8, true)
}

fn swift_timezone_identity(seconds i64) i64 {
	minutes := ((if seconds < 0 { -seconds } else { seconds }) + 30) / 60
	return if seconds < 0 { -minutes } else { minutes }
}

fn swift_timezone_storage_destroy(owner u64) { swift_heap_deallocate(owner, 24, 7) }

fn swift_timezone_bridge(owner u64) u64 {
	seconds := swift_timezone_seconds_checked(owner) or { panic(err) }
	// Native returns a fresh owned Objective-C result without consuming Self.
	// Vinix copies the immutable seconds instead of retaining the Swift owner.
	return ns_timezone_fixed(seconds)
}

fn swift_timezone_emit(code u64, data u64) {
	// Swift Int in x0; owned optional resilient result through x8.
	write32(code + 3032, 0xaa0803e1); write32(code + 3036, 0x58000070); write32(code + 3040, 0xd61f0200)
	unsafe { *(&u64(code + 3048)) = u64(voidptr(swift_timezone_initialize)) }
	entry := code + 3064; metadata := data + 2752; descriptor := data + 2784; witness := data + 2848
	write32(entry, 0x58000080); write32(entry + 4, 0xd2800001); write32(entry + 8, 0xd65f03c0)
	unsafe {
		*(&u64(entry + 16)) = metadata; *(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x200; *(&u64(metadata + 8)) = descriptor
		*(&u64(witness + 64)) = 16; *(&u64(witness + 72)) = 16
	}
	write32(descriptor, 0x51); swift_protocol_relative(descriptor + 4, data + 64)
	swift_protocol_relative(descriptor + 8, data + 2816); swift_protocol_relative(descriptor + 12, entry)
	write32(descriptor + 20, 1); write32(descriptor + 24, 2); C.memcpy(voidptr(data + 2816), c'TimeZone', 9)
	for i, target in [u64(unsafe { voidptr(swift_url_copy) }), u64(unsafe { voidptr(swift_url_destroy) }),
		u64(unsafe { voidptr(swift_url_copy) }), u64(unsafe { voidptr(swift_url_assign_copy) }),
		u64(unsafe { voidptr(swift_url_take) }), u64(unsafe { voidptr(swift_url_assign_take) }),
		u64(unsafe { voidptr(swift_url_enum_get) }), u64(unsafe { voidptr(swift_url_enum_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = target }
	}
	write32(witness + 80, 0x02010007); write32(witness + 84, 0x7fffffff)
	// Borrowed identifier lookup at +32; return owned String in x0/x1.
	for i, op in [u32(0xa9bd57f6), 0xa9014ff4, 0xa9027bfd, 0x910083fd,
		0xa9405693, 0xaa1303e0, 0x580002d0, 0xd63f0200, 0x910082a8,
		0xf94012a9, 0xaa1303f4, 0xaa1503e1, 0xd63f0120, 0xa9427bfd,
		0xa9414ff4, 0xa8c357f6, 0xd65f03c0]! { write32(code + 3096 + u64(i * 4), op) }
	unsafe { *(&u64(code + 3208)) = u64(voidptr(swift_object_type)) }
	write32(code + 3232, 0xaa1403e0); write32(code + 3236, 0x58000070); write32(code + 3240, 0xd61f0200)
	unsafe {
		*(&u64(code + 3248)) = u64(voidptr(swift_timezone_storage_destroy))
		*(&u64(data + 2640)) = code + 3232; *(&u64(data + 2688)) = 2
		*(&u64(data + 2720)) = data + 3200; *(&u64(data + 2992)) = code + 3264
	}
	write32(data + 2696, 2); write32(data + 2704, 24); write32(data + 2708, 7)
	write32(data + 2712, 96); write32(data + 2716, 16)
	write32(data + 3200, 0x50); swift_protocol_relative(data + 3204, data + 64)
	swift_protocol_relative(data + 3208, data + 3264); C.memcpy(voidptr(data + 3264), c'TimeZoneStorage', 16)
	write32(code + 3264, 0xaa1403e0); write32(code + 3268, 0x58000070); write32(code + 3272, 0xd61f0200)
	unsafe { *(&u64(code + 3280)) = u64(voidptr(swift_timezone_identifier)) }
	// Borrow Self; invoke the owned NSTimeZone witness at table +128 with the
	// formal implementation type in x0, table in x1 and slot address in x8.
	for i, op in [u32(0xa9bd57f6), 0xa9014ff4, 0xa9027bfd, 0x910083fd,
		0xa9405693, 0xaa1303e0, 0x580002d0, 0xd63f0200, 0x910202a8,
		0xf94042a9, 0xaa1303f4, 0xaa1503e1, 0xd63f0120, 0xa9427bfd,
		0xa9414ff4, 0xa8c357f6, 0xd65f03c0]! { write32(code + 3520 + u64(i * 4), op) }
	unsafe { *(&u64(code + 3632)) = u64(voidptr(swift_object_type)); *(&u64(data + 3088)) = code + 3664 }
	write32(code + 3664, 0xaa1403e0); write32(code + 3668, 0x58000070); write32(code + 3672, 0xd61f0200)
	unsafe { *(&u64(code + 3680)) = u64(voidptr(swift_timezone_bridge)) }
}
