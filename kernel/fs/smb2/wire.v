// SPDX-License-Identifier: GPL-2.0-or-later
module smb2

pub const capacity = 65536
pub const max_nodes = 512
pub const max_path = 1024
pub const io_size = 32768

// All offsets are relative to the SMB header, excluding the TCP prefix.
pub fn span(total int, offset int, length int) bool {
	return offset >= 0 && length >= 0 && offset <= total && length <= total - offset
}

pub fn get16(p &u8, n int) u16 {
	unsafe {
		return u16(p[n]) | u16(p[n + 1]) << 8
	}
}

pub fn get32(p &u8, n int) u32 {
	unsafe {
		return u32(get16(p, n)) | u32(get16(p, n + 2)) << 16
	}
}

pub fn get64(p &u8, n int) u64 {
	return u64(get32(p, n)) | u64(get32(p, n + 4)) << 32
}

pub fn put16(p &u8, n int, v u16) {
	unsafe {
		p[n] = u8(v)
		p[n + 1] = u8(v >> 8)
	}
}

pub fn put32(p &u8, n int, v u32) {
	put16(p, n, u16(v))
	put16(p, n + 2, u16(v >> 16))
}

pub fn put64(p &u8, n int, v u64) {
	put32(p, n, u32(v))
	put32(p, n + 4, u32(v >> 32))
}

pub fn zero(p &u8, n int) {
	for i in 0 .. n {
		unsafe {
			p[i] = 0
		}
	}
}

pub fn move(dst &u8, src &u8, n int) {
	for i in 0 .. n {
		unsafe {
			dst[i] = src[i]
		}
	}
}

// Strict UTF-8 to UTF-16LE; rejects overlong encodings, surrogates and NUL.
pub fn utf16(s string, out &u8, cap int, upper bool) ?int {
	mut at := 0
	mut i := 0
	for i < s.len {
		b := s[i]
		mut cp := u32(b)
		mut extra := 0
		if b >= 0xc2 && b <= 0xdf {
			cp = u32(b & 31)
			extra = 1
		} else if b >= 0xe0 && b <= 0xef {
			cp = u32(b & 15)
			extra = 2
		} else if b >= 0xf0 && b <= 0xf4 {
			cp = u32(b & 7)
			extra = 3
		} else if b >= 0x80 {
			return none
		}
		if extra > s.len - i - 1 { return none }
		for j in 1 .. extra + 1 {
			c := s[i + j]
			if c & 0xc0 != 0x80 { return none }
			cp = (cp << 6) | u32(c & 63)
		}
		if cp == 0 || (extra == 1 && cp < 0x80) || (extra == 2 && cp < 0x800)
			|| (extra == 3 && cp < 0x10000) || cp > 0x10ffff
			|| (cp >= 0xd800 && cp <= 0xdfff) {
			return none
		}
		// NTLM username case folding is deliberately ASCII-only; refuse rather
		// than silently authenticate with an incorrect Unicode uppercase map.
		if upper && cp > 127 { return none }
		if upper && cp >= 97 && cp <= 122 { cp -= 32 }
		need := if cp > 0xffff { 4 } else { 2 }
		if !span(cap, at, need) { return none }
		if need == 4 {
			put16(out, at, u16(0xd800 + ((cp - 0x10000) >> 10)))
			put16(out, at + 2, u16(0xdc00 + ((cp - 0x10000) & 1023)))
		} else {
			put16(out, at, u16(cp))
		}
		at += need
		i += extra + 1
	}
	return at
}

pub struct Attr {
pub mut:
	size       u64
	allocation u64
	ino        u64
	created    u64
	accessed   u64
	written    u64
	changed    u64
	attributes u32
}

pub fn parse_all_info(p &u8, n int, a &Attr) bool {
	if n < 100 { return false }
	name_len := get32(p, 96)
	if name_len % 2 != 0 || name_len > u32(n - 100) { return false }
	unsafe {
		a.created = get64(p, 0)
		a.accessed = get64(p, 8)
		a.written = get64(p, 16)
		a.changed = get64(p, 24)
		a.attributes = get32(p, 32)
		a.allocation = get64(p, 40)
		a.size = get64(p, 48)
		a.ino = get64(p, 64)
	}
	return get64(p, 48) <= u64(0x7fffffffffffffff)
}

pub struct DirEntry {
pub mut:
	next   int
	length int
	name   [768]u8
	attr   Attr
}

// FILE_ID_BOTH_DIR_INFORMATION. No slices, allocations or trusting NextEntryOffset.
pub fn parse_entry(p &u8, n int, e &DirEntry) bool {
	if n < 104 { return false }
	short_len := int(unsafe { p[68] })
	if short_len > 24 || short_len % 2 != 0 { return false }
	mut extent := n
	next := get32(p, 0)
	if next != 0 {
		if next < 104 || next % 8 != 0 || next > u32(n) { return false }
		extent = int(next)
	}
	bytes := get32(p, 60)
	if bytes % 2 != 0 || bytes > 510 || !span(extent, 104, int(bytes)) { return false }
	mut at := 0
	for i := 0; i < int(bytes); i += 2 {
		cp := get16(p, 104 + i)
		if cp == 0 || cp == 47 || cp == 92 || (cp >= 0xd800 && cp <= 0xdfff) { return false }
		if cp < 128 {
			unsafe {
				e.name[at] = u8(cp)
			}
			at++
		} else if cp < 2048 {
			unsafe {
				e.name[at] = 0xc0 | u8(cp >> 6)
				e.name[at + 1] = 0x80 | u8(cp & 63)
			}
			at += 2
		} else {
			unsafe {
				e.name[at] = 0xe0 | u8(cp >> 12)
				e.name[at + 1] = 0x80 | u8((cp >> 6) & 63)
				e.name[at + 2] = 0x80 | u8(cp & 63)
			}
			at += 3
		}
	}
	unsafe {
		e.length = at
		e.next = int(next)
		e.attr.created = get64(p, 8)
		e.attr.accessed = get64(p, 16)
		e.attr.written = get64(p, 24)
		e.attr.changed = get64(p, 32)
		e.attr.size = get64(p, 40)
		e.attr.allocation = get64(p, 48)
		e.attr.attributes = get32(p, 56)
		e.attr.ino = get64(p, 96)
	}
	return at > 0 && get64(p, 40) <= u64(0x7fffffffffffffff)
}

pub fn status_errno(status u32) int {
	return match status {
		0 { 0 }
		0xc0000022, 0xc000006d, 0xc000006a, 0xc0000064, 0xc0000234 { 13 }
		0xc0000034, 0xc000003a, 0xc00000cc { 2 }
		0xc0000035 { 17 }
		0xc00000ba { 21 }
		0xc0000103 { 20 }
		0xc0000101 { 39 }
		0xc000007f { 28 }
		0xc00000a2 { 30 }
		0xc0000043 { 16 }
		0xc000000d { 22 }
		0xc00000bb { 95 }
		else { 5 }
	}
}
