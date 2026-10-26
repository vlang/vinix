// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

// GetStringUTFChars uses modified UTF-8. Encode actual Unicode, rejecting NUL
// and unpaired surrogates so the C ABI cannot silently truncate or rename keys.
fn ws_account_utf8(e voidptr, value voidptr) &char {
	unsafe {
		if value == nil || pending(e) { return nil }
		n := WsLength(slot(e, 164))(e, value)
		if n < 0 || n > 4096 || pending(e) { return nil }
		chars := WsChars(slot(e, 165))(e, value, nil)
		if chars == nil { return nil }
		defer { WsCharsRelease(slot(e, 166))(e, value, chars) }
		buffer := &u8(C.malloc(usize(n) * 4 + 1))
		if buffer == nil { return nil }
		mut used := i32(0)
		for i := i32(0); i < n; i++ {
			mut code := u32(chars[i])
			if code >= 0xd800 && code <= 0xdbff && i + 1 < n && chars[i + 1] >= 0xdc00 && chars[i + 1] <= 0xdfff {
				i++; code = 0x10000 + ((code - 0xd800) << 10) + u32(chars[i]) - 0xdc00
			} else if code == 0 || (code >= 0xd800 && code <= 0xdfff) { C.free(buffer); return nil }
			if code < 0x80 { buffer[used] = u8(code); used++ }
			else if code < 0x800 {
				buffer[used] = u8(0xc0 | (code >> 6)); buffer[used + 1] = u8(0x80 | (code & 63)); used += 2
			} else if code < 0x10000 {
				buffer[used] = u8(0xe0 | (code >> 12)); buffer[used + 1] = u8(0x80 | ((code >> 6) & 63))
				buffer[used + 2] = u8(0x80 | (code & 63)); used += 3
			} else {
				buffer[used] = u8(0xf0 | (code >> 18)); buffer[used + 1] = u8(0x80 | ((code >> 12) & 63))
				buffer[used + 2] = u8(0x80 | ((code >> 6) & 63)); buffer[used + 3] = u8(0x80 | (code & 63)); used += 4
			}
			if used > 4096 { C.free(buffer); return nil }
		}
		buffer[used] = 0
		return &char(buffer)
	}
}

fn ws_account_java_text(e voidptr, text &char) voidptr {
	unsafe {
		if text == nil || pending(e) { return nil }
		chars := &u16(C.alloca(4096 * sizeof(u16)))
		mut at := usize(0)
		mut count := i32(0)
		n := C.strlen(text)
		if n > 4096 { return nil }
		for at < n {
			first := u8(text[at]); at++
			mut code := u32(first)
			mut extra := i32(0)
			mut minimum := u32(0)
			if first >= 0xc2 && first <= 0xdf { code &= 31; extra = 1; minimum = 0x80 }
			else if first >= 0xe0 && first <= 0xef { code &= 15; extra = 2; minimum = 0x800 }
			else if first >= 0xf0 && first <= 0xf4 { code &= 7; extra = 3; minimum = 0x10000 }
			else if first >= 0x80 { return nil }
			for j := i32(0); j < extra; j++ {
				if at >= n || (u8(text[at]) & 0xc0) != 0x80 { return nil }
				code = (code << 6) | u32(u8(text[at]) & 63); at++
			}
			if code < minimum || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff) { return nil }
			if code >= 0x10000 {
				code -= 0x10000; chars[count] = u16(0xd800 | (code >> 10)); count++
				chars[count] = u16(0xdc00 | (code & 1023)); count++
			} else { chars[count] = u16(code); count++ }
		}
		return WsNewString(slot(e, 163))(e, &chars[0], count)
	}
}
