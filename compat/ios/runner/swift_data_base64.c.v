// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn swift_data_base64_checked(options u64, first u64, second u64) !SwiftStringWords {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return error('iOS: Swift Data base64 outside runtime lifetime')
	}
	if options & ~u64(0x33) != 0 { return error('iOS: unknown NSData base64 encoding options') }
	scratch := u64(C.__builtin_alloca(16))
	source := swift_data_bytes_checked(first, second, scratch)!
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
