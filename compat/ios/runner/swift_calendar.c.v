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
	owner := swift_heap_allocate(data + 1808, 56, 7)
	// The consuming Identifier is POD: only its one readable byte is needed.
	// This owner stores a complete independent snapshot and has no cache retain.
	unsafe {
		*(&u64(owner + 16)) = u64(which)
		*(&u64(owner + 24)) = 0; *(&u64(owner + 32)) = 0
		*(&u64(owner + 40)) = 0; *(&u64(owner + 48)) = 0
		*(&SwiftURLWords(output)) = SwiftURLWords{owner: owner, table: data + 2048}
	}
	if which == 7 {
		text := swift_string_literal(c'en_001', 6, true)
		swift_locale_initialize(text.first, text.second, owner + 24)
	}
}

fn swift_calendar_storage_destroy(owner u64) {
	swift_unknown_release(read64(owner + 24))
	swift_unknown_release(read64(owner + 40))
	swift_heap_deallocate(owner, 56, 7)
}

fn swift_calendar_identifier_checked(owner u64) !u8 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return error('iOS: Swift Calendar outside runtime lifetime')
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	storage := ios_runtime.swift_heap[owner] or { return error('iOS: Swift Calendar requires registered storage') }
	if storage.deiniting || storage.size != 56 || storage.mask != 7
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

fn swift_calendar_day_interval(component u64, date u64, owner u64, output u64) {
	which := swift_calendar_identifier_checked(owner) or { panic(err) }
	if unsafe { *(&u8(component)) } != 3 || which !in [u8(0), 7]! {
		panic('iOS: only Gregorian and ISO 8601 fixed-zone day intervals are implemented')
	}
	zone := read64(owner + 40)
	if zone == 0 { panic('iOS: Swift Calendar requires an explicitly assigned fixed TimeZone') }
	seconds := swift_timezone_seconds_checked(zone) or { panic(err) }
	value := unsafe { *(&f64(date)) }
	if !(value >= -211845067200.0 && value <= 15927175497600.0) { panic('iOS: Calendar day interval requires a clamped Date') }
	// Day boundaries are integral seconds. Floor before dividing so a tiny
	// negative Date cannot underflow to negative zero and select the next day.
	start := C.floor((C.floor(value) + f64(seconds)) / 86400.0) * 86400.0 - f64(seconds)
	unsafe { *(&f64(output)) = start; *(&f64(output + 8)) = 86400.0; *(&u8(output + 16)) = 0 }
}

fn swift_calendar_empty_locale(output u64) {
	swift_locale_initialize(0, 0xe000000000000000, output)
}

fn swift_calendar_locale(owner u64, output u64) {
	swift_calendar_identifier_checked(owner) or { panic(err) }
	words := unsafe { *(&SwiftURLWords(owner + 24)) }
	swift_unknown_retain(words.owner)
	unsafe { *(&SwiftURLWords(output)) = words }
}

fn swift_calendar_locale_input_checked(value u64) !SwiftURLWords {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired || value == 0 {
		return error('iOS: Swift Calendar locale outside runtime lifetime or missing value')
	}
	words := unsafe { *(&SwiftURLWords(value)) }
	if words.owner == 0 { return SwiftURLWords{} }
	if words.table != ios_runtime.swift_foundation_arena + u64(C.getpagesize()) + 1008 {
		return error('iOS: Swift Calendar requires a built-in fixed Locale')
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[words.owner] or { return error('iOS: Swift Calendar requires registered Locale storage') }
	if header.destroyed || read64(words.owner) != ios_runtime.names['NSLocale'] || header.fields[0] == 0 {
		return error('iOS: Swift Calendar requires initialized NSLocale storage')
	}
	return words
}

fn swift_calendar_set_locale(value u64, self u64) {
	words := swift_calendar_locale_input_checked(value) or { panic(err) }
	data := swift_foundation_arena() + u64(C.getpagesize())
	if self == 0 || read64(self + 8) != data + 2048 { panic('iOS: Swift Calendar locale mutation requires built-in Calendar storage') }
	previous := read64(self)
	which := swift_calendar_identifier_checked(previous) or { panic(err) }
	// A nil override means "preserve the locale" in the native copy operation.
	// Consuming nil has no owner; its unused table word need not be interpreted.
	if words.owner == 0 { return }
	current := read64(previous + 24)
	if current != 0 && string_text(swift_locale_require_owner(current)) == string_text(swift_locale_require_owner(words.owner)) {
		swift_unknown_release(words.owner)
		return
	}
	// Owners are immutable after publication. Transfer the consumed Locale to
	// a fresh snapshot before releasing Self's previous owner; borrowed copies
	// keep their original settings and independently retained getter results.
	zone := unsafe { *(&SwiftURLWords(previous + 40)) }
	swift_unknown_retain(zone.owner)
	owner := swift_heap_allocate(data + 1808, 56, 7)
	unsafe {
		*(&u64(owner + 16)) = u64(which)
		*(&SwiftURLWords(owner + 24)) = words
		*(&SwiftURLWords(owner + 40)) = zone
		*(&SwiftURLWords(self)) = SwiftURLWords{owner: owner, table: data + 2048}
	}
	swift_unknown_release(previous)
}

fn swift_calendar_set_zone(value u64, self u64) {
	zone := swift_timezone_input_checked(value) or { panic(err) }
	data := swift_foundation_arena() + u64(C.getpagesize())
	if self == 0 || read64(self + 8) != data + 2048 { panic('iOS: Swift Calendar timezone mutation requires built-in Calendar storage') }
	previous := read64(self)
	which := swift_calendar_identifier_checked(previous) or { panic(err) }
	current := read64(previous + 40)
	if current != 0 {
		old_seconds := swift_timezone_seconds_checked(current) or { panic(err) }
		new_seconds := swift_timezone_seconds_checked(zone.owner) or { panic(err) }
		if swift_timezone_identity(old_seconds) == swift_timezone_identity(new_seconds) {
			swift_unknown_release(zone.owner)
			return
		}
	}
	locale := unsafe { *(&SwiftURLWords(previous + 24)) }
	swift_unknown_retain(locale.owner)
	owner := swift_heap_allocate(data + 1808, 56, 7)
	unsafe {
		*(&u64(owner + 16)) = u64(which)
		*(&SwiftURLWords(owner + 24)) = locale
		*(&SwiftURLWords(owner + 40)) = zone
		*(&SwiftURLWords(self)) = SwiftURLWords{owner: owner, table: data + 2048}
	}
	swift_unknown_release(previous)
}

fn swift_calendar_zone(owner u64, output u64) {
	swift_calendar_identifier_checked(owner) or { panic(err) }
	words := unsafe { *(&SwiftURLWords(owner + 40)) }
	if words.owner == 0 { panic('iOS: Swift Calendar requires an explicitly assigned fixed TimeZone') }
	swift_unknown_retain(words.owner)
	unsafe { *(&SwiftURLWords(output)) = words }
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
	write32(data + 1856, 56); write32(data + 1860, 7)
	write32(data + 1864, 96); write32(data + 1868, 16)
	write32(data + 2560, 0x50)
	swift_protocol_relative(data + 2564, data + 64)
	swift_protocol_relative(data + 2568, data + 2624)
	C.memcpy(voidptr(data + 2624), c'CalendarStorage', 16)
	write32(code + 2592, 0xaa1403e0); write32(code + 2596, 0xaa0803e1)
	write32(code + 2600, 0x58000050); write32(code + 2604, 0xd61f0200)
	unsafe { *(&u64(code + 2608)) = u64(voidptr(swift_calendar_identifier)) }
	// startOfDay(for:): borrow Date in x0 and Calendar in x20, return Date
	// through x8. Clamp the callback's input, preserving the original for the
	// nil-interval fallback. Component.day is one byte; Optional<DateInterval>
	// is two Doubles followed by its one-byte discriminator. Borrowed dispatch
	// passes x2 = formal implementation type, x3 = table, x20 = owner.
	for i, op in [u32(0xd101c3ff), 0x6d0323e9, 0xa90457f6, 0xa9054ff4,
		0xa9067bfd, 0x910183fd, 0xaa0803f3, 0xfd400008, 0xa9405696,
		0x52800068, 0x39005fe8, 0x5c000461, 0x5c000480, 0x1e682000,
		0x1e684c00, 0x1e602020, 0x1e614c00, 0xfd0007e0, 0xaa1603e0,
		0x58000330, 0xd63f0200, 0xaa0003e2, 0xf94052aa, 0x910063e8,
		0x91005fe0, 0x910023e1, 0xaa1603f4, 0xaa1503e3, 0xd63f0140,
		0x3940a3e8, 0x7100051f, 0x54000081, 0x1e7e1000, 0x1e602900,
		0x14000002, 0xfd400fe0, 0xfd000260, 0xa9467bfd, 0xa9454ff4,
		0xa94457f6, 0x6d4323e9, 0x9101c3ff, 0xd65f03c0, 0xd503201f]! {
		write32(code + 2624 + u64(i * 4), op)
	}
	unsafe {
		*(&u64(code + 2800)) = u64(voidptr(swift_object_type))
		*(&u64(code + 2808)) = 0xc248a97998e00000 // -211845067200 seconds since 2001.
		*(&u64(code + 2816)) = 0x42acf8ab468f0000 // 15927175497600 seconds since 2001.
		*(&u64(data + 2208)) = code + 3456
	}
	// Consuming indirect Optional<Locale> in x0; inout Calendar in x20.
	write32(code + 2832, 0xaa1403e1); write32(code + 2836, 0x58000070); write32(code + 2840, 0xd61f0200)
	unsafe { *(&u64(code + 2848)) = u64(voidptr(swift_calendar_set_locale)) }
	// Borrowed generic getter at table +32. A nil implementation locale maps
	// to an owned empty-identifier Locale, as in native Foundation.
	for i, op in [u32(0xa9bd57f6), 0xa9014ff4, 0xa9027bfd, 0x910083fd,
		0xaa0803f3, 0xa9405a95, 0xaa1503e0, 0x580002b0, 0xd63f0200,
		0xaa1603e9, 0xf8420d2a, 0xaa1303e8, 0xaa1503f4, 0xaa1603e1,
		0xd63f0140, 0xf9400269, 0xb5000089, 0xaa1303e0, 0x58000190,
		0xd63f0200, 0xa9427bfd, 0xa9414ff4, 0xa8c357f6, 0xd65f03c0]! {
		write32(code + 2864 + u64(i * 4), op)
	}
	unsafe {
		*(&u64(code + 2976)) = u64(voidptr(swift_object_type))
		*(&u64(code + 2984)) = u64(voidptr(swift_calendar_empty_locale))
		*(&u64(data + 2080)) = code + 3008
	}
	write32(code + 3008, 0xaa1403e0); write32(code + 3012, 0xaa0803e1)
	write32(code + 3016, 0x58000050); write32(code + 3020, 0xd61f0200)
	unsafe { *(&u64(code + 3024)) = u64(voidptr(swift_calendar_locale)) }
	write32(code + 3296, 0xaa1403e1); write32(code + 3300, 0x58000070); write32(code + 3304, 0xd61f0200)
	unsafe { *(&u64(code + 3312)) = u64(voidptr(swift_calendar_set_zone)) }
	// Generic borrowed TimeZone getter at +48, with an owned sixteen-byte result.
	for i, op in [u32(0xa9bd57f6), 0xa9014ff4, 0xa9027bfd, 0x910083fd,
		0xaa0803f3, 0xa9405a95, 0xaa1503e0, 0x580002b0, 0xd63f0200,
		0xaa1603e9, 0xf8430d2a, 0xaa1303e8, 0xaa1503f4, 0xaa1603e1,
		0xd63f0140, 0xa9427bfd, 0xa9414ff4, 0xa8c357f6, 0xd65f03c0]! {
		write32(code + 3328 + u64(i * 4), op)
	}
	unsafe {
		*(&u64(code + 3440)) = u64(voidptr(swift_object_type))
		*(&u64(data + 2096)) = code + 3488
	}
	write32(code + 3456, 0xaa1403e2); write32(code + 3460, 0xaa0803e3)
	write32(code + 3464, 0x58000050); write32(code + 3468, 0xd61f0200)
	unsafe { *(&u64(code + 3472)) = u64(voidptr(swift_calendar_day_interval)) }
	write32(code + 3488, 0xaa1403e0); write32(code + 3492, 0xaa0803e1)
	write32(code + 3496, 0x58000050); write32(code + 3500, 0xd61f0200)
	unsafe { *(&u64(code + 3504)) = u64(voidptr(swift_calendar_zone)) }
}
