// SPDX-License-Identifier: GPL-2.0-or-later
module ansreads

// Unicode 13 decimal category Nd, matching the former command's host parser.
const decimal_zeros = [0x30, 0x660, 0x6f0, 0x7c0, 0x966, 0x9e6, 0xa66, 0xae6, 0xb66, 0xbe6, 0xc66,
	0xce6, 0xd66, 0xde6, 0xe50, 0xed0, 0xf20, 0x1040, 0x1090, 0x17e0, 0x1810, 0x1946, 0x19d0, 0x1a80,
	0x1a90, 0x1b50, 0x1bb0, 0x1c40, 0x1c50, 0xa620, 0xa8d0, 0xa900, 0xa9d0, 0xa9f0, 0xaa50, 0xabf0,
	0xff10, 0x104a0, 0x10d30, 0x11066, 0x110f0, 0x11136, 0x111d0, 0x112f0, 0x11450, 0x114d0, 0x11650,
	0x116c0, 0x11730, 0x118e0, 0x11950, 0x11c50, 0x11d50, 0x11da0, 0x16a60, 0x16b50, 0x1d7ce, 0x1d7d8,
	0x1d7e2, 0x1d7ec, 0x1d7f6, 0x1e140, 0x1e2f0, 0x1e950, 0x1fbf0]

fn integer_space(ch rune) bool {
	return ch in [rune(9), 10, 11, 12, 13, 32, 0x85, 0xa0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003,
		0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a, 0x2028, 0x2029, 0x202f, 0x205f,
		0x3000]
}

fn bounded_integer(raw string, base int) !i64 {
	mut normalized := []u8{cap: raw.len}
	runes := raw.runes()
	mut first := 0
	mut end := runes.len
	for first < end && integer_space(runes[first]) { first++ }
	for end > first && integer_space(runes[end - 1]) { end-- }
	for ch in runes[first..end] {
		mut digit := -1
		for zero in decimal_zeros {
			if ch >= zero && ch < zero + 10 {
				digit = int(ch) - zero
				break
			}
		}
		if digit >= 0 {
			normalized << u8(`0` + digit)
		} else if ch < 128 {
			normalized << u8(ch)
		} else {
			return error('invalid integer: ' + raw)
		}
	}
	text := normalized.bytestr()
	mut position := 0
	negative := text.starts_with('-')
	if negative || text.starts_with('+') { position++ }
	mut radix := base
	mut prefixed := false
	if base == 0 {
		radix = 10
		if position + 2 <= text.len && text[position] == `0` {
			marker := text[position + 1]
			if marker in [`x`, `X`, `o`, `O`, `b`, `B`] {
				radix = if marker in [`x`, `X`] {
					16
				} else if marker in [`o`, `O`] {
					8
				} else {
					2
				}
				position += 2
				prefixed = true
			}
		}
	}
	leading_zero := base == 0 && !prefixed && position < text.len && text[position] == `0`
	mut previous := false
	mut digits := 0
	mut magnitude := u64(0)
	mut overflow := false
	mut nonzero := false
	limit := u64(max_offset) + if negative { u64(1) } else { u64(0) }
	for index in position .. text.len {
		ch := text[index]
		if ch == `_` {
			if (!previous && !(prefixed && index == position)) || index + 1 == text.len {
				return error('invalid integer: ' + raw)
			}
			previous = false
			continue
		}
		digit := if ch >= `0` && ch <= `9` {
			int(ch - `0`)
		} else if ch >= `a` && ch <= `f` {
			int(ch - `a`) + 10
		} else if ch >= `A` && ch <= `F` {
			int(ch - `A`) + 10
		} else {
			-1
		}
		if digit < 0 || digit >= radix { return error('invalid integer: ' + raw) }
		if magnitude > (limit - u64(digit)) / u64(radix) { overflow = true }
		if !overflow { magnitude = magnitude * u64(radix) + u64(digit) }
		nonzero = nonzero || digit != 0
		previous = true
		digits++
	}
	if digits == 0 || (leading_zero && nonzero) { return error('invalid integer: ' + raw) }
	if overflow { return error('integer exceeds signed 64-bit bounds') }
	if negative {
		if magnitude == u64(max_offset) + 1 { return -max_offset - 1 }
		return -i64(magnitude)
	}
	return i64(magnitude)
}

pub fn parse_range(text string) !Range {
	pieces := text.split(':')
	if pieces.len != 2 { return error('range requires OFFSET:LENGTH') }
	return checked_range(bounded_integer(pieces[0], 0)!, bounded_integer(pieces[1], 0)!)!
}
