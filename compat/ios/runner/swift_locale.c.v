// SPDX-License-Identifier: GPL-2.0-or-later
module main

// A bounded fixed-locale profile. Native preserves region separators, uses
// a hyphen before scripts, and canonicalizes component case. Keywords,
// extensions and the broader ICU alias database need a separate profile.
fn swift_locale_canonical_checked(first u64, second u64, output u64) !int {
	scratch := u64(C.__builtin_alloca(16))
	bytes := swift_string_bytes(SwiftStringWords{first: first, second: second}, scratch)!
	if bytes.count > 128 { return error('iOS: Swift Locale identifier exceeds supported length') }
	if bytes.count == 0 { return 0 }
	count := int(bytes.count)
	C.memcpy(voidptr(output), voidptr(bytes.address), usize(count))
	mut end := 0
	for end < count && unsafe { *(&u8(output + u64(end))) } !in [u8(`_`), `-`]! { end++ }
	for i in 0 .. end {
		byte := unsafe { *(&u8(output + u64(i))) }
		if !((byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`)) {
			return error('iOS: unsupported Swift Locale language')
		}
		unsafe { *(&u8(output + u64(i))) = byte | 32 }
	}
	language := unsafe { tos(&u8(output), end) }
	if language !in ['en', 'de', 'fr', 'ru', 'zh', 'sr', 'es', 'pt', 'ja', 'ko', 'it', 'ar',
		'he', 'hi', 'id', 'yi', 'c', 'posix', 'iw', 'in', 'ji']! {
		return error('iOS: Swift Locale language canonicalization is not implemented')
	}
	alias := match language { 'iw' { 'he' } 'in' { 'id' } 'ji' { 'yi' } else { '' } }
	if alias != '' { C.memcpy(voidptr(output), alias.str, 2) }
	mut script := false
	mut region := false
	mut variant := false
	for end < count {
		separator := end
		start := end + 1
		end = start
		mut alpha := true
		mut digit := true
		for end < count && unsafe { *(&u8(output + u64(end))) } !in [u8(`_`), `-`]! {
			byte := unsafe { *(&u8(output + u64(end))) }
			alpha = alpha && ((byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`))
			digit = digit && byte >= `0` && byte <= `9`
			end++
		}
		length := end - start
		if length == 4 && alpha && !script && !region && !variant {
			if unsafe { *(&u8(output + u64(separator))) } == `_` {
				for i in start .. end {
					byte := unsafe { *(&u8(output + u64(i))) }
					if (i == start && (byte < `A` || byte > `Z`)) || (i != start && (byte < `a` || byte > `z`)) {
						return error('iOS: noncanonical legacy Swift Locale scripts are not implemented')
					}
				}
			}
			unsafe { *(&u8(output + u64(separator))) = `-` }
			for i in start .. end { unsafe { *(&u8(output + u64(i))) = if i == start { *(&u8(output + u64(i))) & ~u8(32) } else { *(&u8(output + u64(i))) | 32 } } }
			script = true
		} else if !region && !variant && ((length == 2 && alpha) || (length == 3 && digit) || (length == 0 && end < count)) {
			for i in start .. end { if alpha { unsafe { *(&u8(output + u64(i))) &= ~u8(32) } } }
			region = true
		} else if length == 5 && alpha && !variant {
			for i in start .. end { unsafe { *(&u8(output + u64(i))) &= ~u8(32) } }
			if C.memcmp(voidptr(output + u64(start)), c'POSIX', 5) != 0 { return error('iOS: unsupported Swift Locale variant') }
			if unsafe { *(&u8(output + u64(separator))) } == `-` {
				for i in start .. end { unsafe { *(&u8(output + u64(i))) |= 32 } }
			}
			variant = true
		} else { return error('iOS: unsupported Swift Locale identifier form') }
	}
	return count
}

fn swift_locale_initialize(first u64, second u64, output u64) {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		panic('iOS: Swift Locale construction outside runtime lifetime')
	}
	buffer := u64(C.__builtin_alloca(128))
	count := swift_locale_canonical_checked(first, second, buffer) or { panic(err) }
	identifier := owned_string(unsafe { tos(&u8(buffer), count) })
	owner := objc_allocate(ios_runtime.names['NSLocale'])
	store_field(owner, 0, identifier)
	objc_release(identifier)
	swift_bridge_release(second) // The String argument is consumed, including heap storage.
	unsafe { *(&SwiftURLWords(output)) = SwiftURLWords{owner: owner, table: swift_foundation_arena() + u64(C.getpagesize()) + 1008} }
}

fn swift_locale_require_owner(owner u64) u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { panic('iOS: Swift Locale outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[owner] or { panic('iOS: Swift Locale requires a registered NSLocale') }
	if header.destroyed || read64(owner) != ios_runtime.names['NSLocale'] || header.fields[0] == 0 {
		panic('iOS: Swift Locale requires initialized built-in NSLocale')
	}
	return header.fields[0]
}

fn swift_locale_identifier(owner u64) SwiftStringWords {
	return swift_foundation_unbridge(swift_locale_require_owner(owner))
}

fn swift_locale_bridge(owner u64) u64 {
	swift_locale_require_owner(owner)
	return objc_retain(owner)
}

fn swift_locale_emit(code u64, data u64) {
	// Consuming String in x0/x1, resilient two-word result through x8.
	write32(code + 1952, 0xaa0803e2)
	write32(code + 1956, 0x58000070)
	write32(code + 1960, 0xd61f0200)
	unsafe { *(&u64(code + 1968)) = u64(voidptr(swift_locale_initialize)) }
	for i, slot in [u64(488), 64]! {
		entry := code + 1984 + u64(i * 128)
		// Borrow Self, discover the implementation's formal type, then call
		// its owned NSLocale/String witness with native metadata/table context.
		for j, op in [u32(0xa9bd57f6), 0xa9014ff4, 0xa9027bfd, 0x910083fd,
			0xa9405693, 0xaa1303e0, 0x580002d0, 0xd63f0200,
			0x910002a8 | (u32(slot) << 10), 0xf94002a9 | (u32(slot / 8) << 10),
			0xaa1303f4, 0xaa1503e1, 0xd63f0120, 0xa9427bfd, 0xa9414ff4, 0xa8c357f6, 0xd65f03c0]! {
			write32(entry + u64(j * 4), op)
		}
		unsafe { *(&u64(entry + 112)) = u64(voidptr(swift_object_type)) }
	}
	for i, target in [u64(unsafe { voidptr(swift_locale_identifier) }), u64(unsafe { voidptr(swift_locale_bridge) })]! {
		entry := code + 2240 + u64(i * 32)
		write32(entry, 0xaa1403e0); write32(entry + 4, 0x58000070); write32(entry + 8, 0xd61f0200)
		unsafe { *(&u64(entry + 16)) = target }
	}
	metadata := data + 816
	descriptor := data + 848
	witness := data + 896
	entry := code + 2304
	write32(entry, 0x58000080); write32(entry + 4, 0xd2800001); write32(entry + 8, 0xd65f03c0)
	unsafe {
		*(&u64(entry + 16)) = metadata
		*(&u64(metadata - 8)) = witness; *(&u64(metadata)) = 0x200; *(&u64(metadata + 8)) = descriptor
		*(&u64(witness + 64)) = 16; *(&u64(witness + 72)) = 16
		*(&u64(data + 1072)) = code + 2240; *(&u64(data + 1496)) = code + 2272
	}
	write32(descriptor, 0x51)
	swift_protocol_relative(descriptor + 4, data + 64)
	swift_protocol_relative(descriptor + 8, data + 880)
	swift_protocol_relative(descriptor + 12, entry)
	write32(descriptor + 20, 1); write32(descriptor + 24, 2)
	C.memcpy(voidptr(data + 880), c'Locale', 7)
	// Native Locale has the same unknown-object/table ownership layout as URL.
	for i, target in [u64(unsafe { voidptr(swift_url_copy) }), u64(unsafe { voidptr(swift_url_destroy) }),
		u64(unsafe { voidptr(swift_url_copy) }), u64(unsafe { voidptr(swift_url_assign_copy) }),
		u64(unsafe { voidptr(swift_url_take) }), u64(unsafe { voidptr(swift_url_assign_take) }),
		u64(unsafe { voidptr(swift_url_enum_get) }), u64(unsafe { voidptr(swift_url_enum_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = target }
	}
	write32(witness + 80, 0x02010007); write32(witness + 84, 0x7fffffff)
}
