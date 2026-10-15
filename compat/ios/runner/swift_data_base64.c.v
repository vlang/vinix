// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn swift_data_base64_bytes(first u64, second u64, scratch u64) !SwiftStringBytes {
	match second >> 62 {
		3 { return SwiftStringBytes{} }
		0 {
			count := (second >> 48) & 0xff
			if count > 14 { return error('iOS: invalid inline Swift Data length') }
			unsafe { *(&SwiftDataWords(scratch)) = SwiftDataWords{ first: first, second: second } }
			return SwiftStringBytes{ address: scratch, count: count }
		}
		1 {
			start := i64(i32(u32(first)))
			end := i64(i32(u32(first >> 32)))
			if start == end { return SwiftStringBytes{} }
			if start < 0 || end < start { return error('iOS: invalid Swift Data slice range') }
			owner := second & u64(0x3fffffffffffffff)
			C.ios_objc_initialize_lock()
			defer { C.ios_objc_initialize_unlock() }
			storage := ios_runtime.swift_heap[owner] or {
				return error('iOS: Swift Data base64 requires registered snapshot storage')
			}
			if storage.deiniting || storage.size != 65 || storage.mask != 7
				|| ios_runtime.swift_foundation_arena == 0
				|| storage.metadata != ios_runtime.swift_foundation_arena + u64(C.getpagesize()) + 400
				|| read64(owner) != storage.metadata || read64(owner + 24) > 16777216
				|| u64(end) > read64(owner + 24) || read64(owner + 16) == 0
				|| read64(owner + 32) != 0 || read64(owner + 40) != 0 || read64(owner + 56) != 0 {
				return error('iOS: unsupported Swift Data snapshot layout or range')
			}
			// Swift borrows Data throughout the call. Its caller keeps this byte
			// span alive; no retain, mutation or guest callback is needed here.
			return SwiftStringBytes{ address: read64(owner + 16) + u64(start), count: u64(end - start) }
		}
		else { return error('iOS: large-range Swift Data base64 is not implemented') }
	}
}

fn swift_data_base64_checked(options u64, first u64, second u64) !SwiftStringWords {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return error('iOS: Swift Data base64 outside runtime lifetime')
	}
	if options & ~u64(0x33) != 0 { return error('iOS: unknown NSData base64 encoding options') }
	scratch := u64(C.__builtin_alloca(16))
	source := swift_data_base64_bytes(first, second, scratch)!
	if source.count == 0 { return swift_string_empty() }
	// Native chooses 64 columns when both line-length bits are present and
	// inserts separators only between lines, never at the end of the result.
	width := if options & 1 != 0 {
		u64(64)
	} else if options & 2 != 0 {
		u64(76)
	} else {
		u64(0)
	}
	cr := options & 0x30 == 0 || options & 0x10 != 0
	lf := options & 0x30 == 0 || options & 0x20 != 0
	encoded := ((source.count + 2) / 3) * 4
	separators := if width == 0 { u64(0) } else { (encoded - 1) / width }
	total := encoded + separators * (u64(cr) + u64(lf))
	mut result := swift_string_empty()
	inline_bytes := u64(C.__builtin_alloca(16))
	C.memset(voidptr(inline_bytes), 0, 16)
	mut output := inline_bytes
	if total > 15 {
		C.ios_objc_initialize_lock()
		result = swift_string_storage(total, total, true)
		C.ios_objc_initialize_unlock()
		output = result.second + 32
	}
	alphabet := c'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
	mut at := u64(0)
	mut column := u64(0)
	for i := u64(0); i < source.count; i += 3 {
		if width != 0 && column == width {
			if cr {
				unsafe { *(&u8(output + at)) = `\r` }
				at++
			}
			if lf {
				unsafe { *(&u8(output + at)) = `\n` }
				at++
			}
			column = 0
		}
		a := unsafe { *(&u8(source.address + i)) }
		b := if i + 1 < source.count { unsafe { *(&u8(source.address + i + 1)) } } else { u8(0) }
		c := if i + 2 < source.count { unsafe { *(&u8(source.address + i + 2)) } } else { u8(0) }
		unsafe {
			*(&u8(output + at)) = u8(alphabet[a >> 2])
			*(&u8(output + at + 1)) = u8(alphabet[((a & 3) << 4) | (b >> 4)])
			*(&u8(output + at + 2)) = if i + 1 < source.count {
				u8(alphabet[((b & 15) << 2) | (c >> 6)])
			} else {
				`=`
			}
			*(&u8(output + at + 3)) = if i + 2 < source.count { u8(alphabet[c & 63]) } else { `=` }
		}
		at += 4
		column += 4
	}
	if at != total { panic('iOS: inconsistent Swift Data base64 output size') }
	return if total <= 15 {
		swift_string_literal(unsafe { &u8(inline_bytes) }, i64(total), true)
	} else {
		result
	}
}

// Native ABI: options in x0, borrowed Data in x1/x2, owned String in x0/x1.
fn swift_data_base64(options u64, first u64, second u64) SwiftStringWords {
	return swift_data_base64_checked(options, first, second) or { panic(err) }
}
