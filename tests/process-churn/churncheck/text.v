// SPDX-License-Identifier: GPL-2.0-or-later
module churncheck

import hosttest
import math.big

// Decimal category Nd in the original Unicode 13 report parser.
const decimal_zeros = [0x30, 0x660, 0x6f0, 0x7c0, 0x966, 0x9e6, 0xa66, 0xae6, 0xb66, 0xbe6, 0xc66,
	0xce6, 0xd66, 0xde6, 0xe50, 0xed0, 0xf20, 0x1040, 0x1090, 0x17e0, 0x1810, 0x1946, 0x19d0, 0x1a80,
	0x1a90, 0x1b50, 0x1bb0, 0x1c40, 0x1c50, 0xa620, 0xa8d0, 0xa900, 0xa9d0, 0xa9f0, 0xaa50, 0xabf0,
	0xff10, 0x104a0, 0x10d30, 0x11066, 0x110f0, 0x11136, 0x111d0, 0x112f0, 0x11450, 0x114d0, 0x11650,
	0x116c0, 0x11730, 0x118e0, 0x11950, 0x11c50, 0x11d50, 0x11da0, 0x16a60, 0x16b50, 0x1d7ce, 0x1d7d8,
	0x1d7e2, 0x1d7ec, 0x1d7f6, 0x1e140, 0x1e2f0, 0x1e950, 0x1fbf0]

fn space(character rune) bool {
	return character in [rune(9), 10, 11, 12, 13, 28, 29, 30, 31, 32, 0x85, 0xa0, 0x1680, 0x2000,
		0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a, 0x2028,
		0x2029, 0x202f, 0x205f, 0x3000]
}

fn stripped(text string) string {
	runes := text.runes()
	mut start := 0
	mut end := runes.len
	for start < end && space(runes[start]) { start++ }
	for end > start && space(runes[end - 1]) { end-- }
	return runes[start..end].string()
}

// Consume maximal valid prefixes of malformed UTF-8, then universal newlines,
// matching the former log read's replacement decoding.
pub fn log_text(raw string) string {
	mut result := []u8{cap: raw.len}
	mut pos := 0
	for pos < raw.len {
		first := raw[pos]
		if first < 0x80 {
			result << first
			pos++
			continue
		}
		length := if first >= 0xc2 && first <= 0xdf {
			2
		} else if first >= 0xe0 && first <= 0xef {
			3
		} else if first >= 0xf0 && first <= 0xf4 {
			4
		} else {
			0
		}
		mut consumed := 1
		if length != 0 {
			for consumed < length && pos + consumed < raw.len {
				byte := raw[pos + consumed]
				if byte < 0x80 || byte > 0xbf { break }
				if consumed == 1 && ((first == 0xe0 && byte < 0xa0) || (first == 0xed && byte > 0x9f)
					|| (first == 0xf0 && byte < 0x90) || (first == 0xf4 && byte > 0x8f)) {
					break
				}
				consumed++
			}
		}
		if length != 0 && consumed == length {
			result << raw[pos..pos + consumed].bytes()
		} else {
			result << [u8(0xef), 0xbf, 0xbd]
		}
		pos += consumed
	}
	return result.bytestr().replace('\r\n', '\n').replace('\r', '\n')
}

fn lines(source string) []string {
	mut text := source
	for delimiter in ['\v', '\f', '\x1c', '\x1d', '\x1e', '\u0085', '\u2028', '\u2029'] {
		text = text.replace(delimiter, '\n')
	}
	return text.split('\n')
}

// Match (\w+)=([^\s]+), including keys after punctuation and '=' in values.
pub fn fields(line string) !map[string]string {
	runes := line.runes()
	mut result := map[string]string{}
	mut cursor := 0
	for cursor < runes.len {
		if !hosttest.module_word_rune(runes[cursor]) {
			cursor++
			continue
		}
		start := cursor
		for cursor < runes.len && hosttest.module_word_rune(runes[cursor]) { cursor++ }
		end := cursor
		if cursor + 1 >= runes.len || runes[cursor] != `=` || space(runes[cursor + 1]) { continue }
		cursor++
		value := cursor
		for cursor < runes.len && !space(runes[cursor]) { cursor++ }
		key := runes[start..end].string()
		if key in result { return error('duplicate ${key}: ${line}') }
		result[key] = runes[value..cursor].string()
	}
	return result
}

fn required(row map[string]string, key string) !string {
	return row[key] or { return error("'${key}'") }
}

fn digit(character rune) int {
	for zero in decimal_zeros {
		if character >= zero && character < zero + 10 { return int(character) - zero }
	}
	return -1
}

fn quoted(text string) string {
	quote := if text.contains("'") && !text.contains('"') { `"` } else { `'` }
	mut result := quote.str()
	for character in text.runes() {
		if character == rune(quote) || character == `\\` {
			result += '\\' + character.str()
		} else if character == `\n` {
			result += '\\n'
		} else if character == `\r` {
			result += '\\r'
		} else if character == `\t` {
			result += '\\t'
		} else if character < 32 || (character >= 127 && character <= 159) {
			result += '\\x${int(character):02x}'
		} else {
			result += character.str()
		}
	}
	return result + quote.str()
}

pub fn integer(raw string, radix int) !big.Integer {
	mut normalized := []u8{cap: raw.len}
	for character in raw.runes() {
		value := digit(character)
		if value >= 0 {
			normalized << u8(`0` + value)
		} else if character < 128 {
			normalized << u8(character)
		} else {
			return error('invalid literal for int() with base ${radix}: ${quoted(raw)}')
		}
	}
	text := normalized.bytestr()
	mut start := if text.starts_with('+') || text.starts_with('-') { 1 } else { 0 }
	mut clean := if start > 0 { text[..1] } else { '' }
	mut prefixed := false
	if radix == 16 && text[start..].to_lower().starts_with('0x') {
		start += 2
		prefixed = true
	}
	mut previous := false
	mut digits := 0
	for index in start .. text.len {
		character := text[index]
		if character == `_` {
			if (!previous && !(prefixed && index == start)) || index + 1 == text.len {
				return error('invalid literal for int() with base ${radix}: ${quoted(raw)}')
			}
			previous = false
			continue
		}
		value := if character >= `0` && character <= `9` {
			int(character - `0`)
		} else if character >= `a` && character <= `f` {
			int(character - `a`) + 10
		} else if character >= `A` && character <= `F` {
			int(character - `A`) + 10
		} else {
			-1
		}
		if value < 0 || value >= radix {
			return error('invalid literal for int() with base ${radix}: ${quoted(raw)}')
		}
		clean += character.ascii_str()
		previous = true
		digits++
	}
	if digits == 0 { return error('invalid literal for int() with base ${radix}: ${quoted(raw)}') }
	return big.integer_from_radix(clean, u32(radix))!
}

fn integer_field(row map[string]string, key string) !big.Integer {
	return integer(required(row, key)!, 10)!
}

fn summary(line string) ?(big.Integer, big.Integer) {
	at := line.last_index(' live ') or { return none }
	parts := line[at + 6..].split(' dropped ')
	if parts.len != 2 || parts.any(it == '' || !it.runes().all(digit(it) >= 0)) { return none }
	live := integer(parts[0], 10) or { return none }
	dropped := integer(parts[1], 10) or { return none }
	return live, dropped
}
