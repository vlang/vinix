// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn ns_string_cstring_output(object u64, encoding u64) u64 {
	if encoding !in [u64(1), 4, 5]! {
		panic('iOS: cStringUsingEncoding supports ASCII, UTF8 and Latin1 only')
	}
	// Snapshot while locked: mutable receivers can replace and free their bytes.
	C.ios_objc_initialize_lock()
	source := cf_string_compare_text(object) or {
		C.ios_objc_initialize_unlock()
		panic('iOS: cStringUsingEncoding requires a live UTF8 string')
	}
	text := source.clone()
	C.ios_objc_initialize_unlock()
	defer { unsafe { text.free() } }
	bytes := ns_string_cstring_bytes(text, encoding) or { return 0 }
	// Drop the lock before class initialization/allocation callbacks. NSData's
	// normal destructor frees this buffer when the caller's pool drains. Its
	// lifetime is at least the NSString inner-pointer contract (receiver/pool).
	holder := objc_allocate(ios_runtime.names['NSData'])
	if holder == 0 { unsafe { bytes.free() }; return 0 }
	mut header := obj_header(holder)
	header.data = bytes
	objc_autorelease(holder)
	return u64(bytes.data)
}

// Includes the terminator; the caller owns the returned buffer.
fn ns_string_cstring_bytes(text string, encoding u64) ?[]u8 {
	mut bytes := []u8{len: text.len + 1}
	mut length := 0
	if encoding == 4 {
		if text.len != 0 { unsafe { C.memcpy(bytes.data, text.str, usize(text.len)) } }
		length = text.len
	} else {
		mut cursor := CFStringCompareCursor{text: text}
		limit := if encoding == 5 { u32(0xff) } else { u32(0x7f) }
		for {
			unit := cursor.next()
			if unit == 0x10000 { break }
			if unit > limit {
				// Latin-1 combines accents with the preceding character, but
				// does not decompose aliases such as the Angstrom symbol.
				if encoding == 5 && length > 0 {
					combined := swift_nfc_compose(u32(bytes[length - 1]), unit)
					if combined != 0 && combined <= limit {
						bytes[length - 1] = u8(combined)
						continue
					}
				}
				unsafe { bytes.free() }
				return none
			}
			bytes[length] = u8(unit)
			length++
		}
	}
	bytes[length] = 0
	bytes.trim(length + 1)
	return bytes
}

fn ns_string_get_cstring(object u64, buffer u64, capacity u64, encoding u64) u64 {
	if encoding !in [u64(1), 4, 5]! {
		panic('iOS: getCString supports ASCII, UTF8 and Latin1 only')
	}
	if capacity == 0 || buffer == 0 { return 0 }
	// Copy before unlocking: a mutable receiver can replace its storage.
	C.ios_objc_initialize_lock()
	source := cf_string_compare_text(object) or {
		C.ios_objc_initialize_unlock()
		panic('iOS: getCString requires a live UTF8 string')
	}
	text := source.clone()
	C.ios_objc_initialize_unlock()
	defer { unsafe { text.free() } }
	bytes := ns_string_cstring_bytes(text, encoding) or {
		unsafe { (&u8(voidptr(buffer)))[0] = 0 }
		return 0
	}
	defer { unsafe { bytes.free() } }
	if u64(bytes.len) > capacity {
		unsafe { (&u8(voidptr(buffer)))[0] = 0 }
		return 0
	}
	unsafe { C.memcpy(voidptr(buffer), bytes.data, usize(bytes.len)) }
	return 1
}
