// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8
import math

const json_size_limit = 16777216
const json_depth_limit = 64

struct JsonInput {
	bytes []u8
	owned bool
}

struct JsonReader {
	bytes   []u8
	options u64
mut:
	position int
	nodes    int
}

fn json_utf8(mut out []u8, code u32) ! {
	if code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff) {
		return json_failure('Invalid Unicode scalar')
	}
	if out.len > json_size_limit - 4 { return json_failure('JSON text exceeds size limit') }
	if code < 0x80 {
		out << u8(code)
	} else if code < 0x800 {
		out << u8(0xc0 | code >> 6)
		out << u8(0x80 | code & 63)
	} else if code < 0x10000 {
		out << u8(0xe0 | code >> 12)
		out << u8(0x80 | (code >> 6) & 63)
		out << u8(0x80 | code & 63)
	} else {
		out << u8(0xf0 | code >> 18)
		out << u8(0x80 | (code >> 12) & 63)
		out << u8(0x80 | (code >> 6) & 63)
		out << u8(0x80 | code & 63)
	}
}

fn json_input(bytes []u8) !JsonInput {
	if bytes.len == 0 { return json_failure('Unexpected end of JSON') }
	mut offset := 0
	mut width := 1
	mut little := false
	if bytes.len >= 4 {
		if bytes[0] == 0xff && bytes[1] == 0xfe && bytes[2] == 0 && bytes[3] == 0 {
			offset = 4
			width = 4
			little = true
		} else if bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0xfe && bytes[3] == 0xff {
			offset = 4
			width = 4
		} else if bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0 {
			width = 4
		} else if bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0 {
			width = 4
			little = true
		}
	}
	if width == 1 && bytes.len >= 2 {
		if bytes[0] == 0xfe && bytes[1] == 0xff {
			offset = 2
			width = 2
		} else if bytes[0] == 0xff && bytes[1] == 0xfe {
			offset = 2
			width = 2
			little = true
		} else if bytes[0] == 0 {
			width = 2
		} else if bytes[1] == 0 {
			width = 2
			little = true
		}
	}
	if width == 1 {
		if bytes.len >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf { offset = 3 }
		// This slice is a borrowed header, never freed by its caller.
		data := unsafe { (&u8(u64(bytes.data) + u64(offset))).vbytes(bytes.len - offset) }
		if !utf8.validate_str(unsafe { tos(data.data, data.len) }) {
			return json_failure('Invalid UTF-8 JSON')
		}
		return JsonInput{ bytes: data }
	}
	if (bytes.len - offset) % width != 0 { return json_failure('Truncated Unicode JSON') }
	mut out := []u8{cap: bytes.len}
	out.flags |= .noslices
	mut complete := false
	defer { if !complete { unsafe { out.free() } } }
	for offset < bytes.len {
		mut code := u32(0)
		for i in 0 .. width {
			code |= u32(bytes[offset + i]) << u32(8 * if little { i } else { width - 1 - i })
		}
		offset += width
		if width == 2 && code >= 0xd800 && code <= 0xdbff {
			if offset >= bytes.len { return json_failure('Missing Unicode surrogate') }
			low := if little {
				u32(bytes[offset]) | u32(bytes[offset + 1]) << 8
			} else {
				u32(bytes[offset]) << 8 | u32(bytes[offset + 1])
			}
			if low < 0xdc00 || low > 0xdfff { return json_failure('Invalid Unicode surrogate') }
			code = 0x10000 + ((code - 0xd800) << 10) + low - 0xdc00
			offset += 2
		}
		json_utf8(mut out, code)!
	}
	complete = true
	return JsonInput{ bytes: out, owned: true }
}

fn (mut reader JsonReader) whitespace() {
	for reader.position < reader.bytes.len && reader.bytes[reader.position] in [u8(9), 10, 13,
		32]! {
		reader.position++
	}
}

fn (mut reader JsonReader) take(value u8) bool {
	if reader.position < reader.bytes.len && reader.bytes[reader.position] == value {
		reader.position++
		return true
	}
	return false
}

fn (mut reader JsonReader) literal(text string) bool {
	if reader.bytes.len - reader.position < text.len { return false }
	for i, byte in text { if reader.bytes[reader.position + i] != byte { return false } }
	reader.position += text.len
	return true
}

fn (mut reader JsonReader) hex() !u32 {
	if reader.bytes.len - reader.position < 4 { return json_failure('Truncated Unicode escape') }
	mut code := u32(0)
	for _ in 0 .. 4 {
		byte := reader.bytes[reader.position]
		reader.position++
		value := if byte >= `0` && byte <= `9` {
			byte - `0`
		} else if byte >= `a` && byte <= `f` {
			byte - `a` + 10
		} else if byte >= `A` && byte <= `F` {
			byte - `A` + 10
		} else {
			return json_failure('Invalid Unicode escape')
		}
		code = (code << 4) | u32(value)
	}
	return code
}

fn (mut reader JsonReader) text() !u64 {
	if !reader.take(`"`) { return json_failure('Expected JSON string') }
	mut out := []u8{cap: 32}
	out.flags |= .noslices
	defer { unsafe { out.free() } }
	for reader.position < reader.bytes.len {
		byte := reader.bytes[reader.position]
		reader.position++
		if byte == `"` { return owned_string(unsafe { tos(out.data, out.len) }) }
		if byte < 32 { return json_failure('Unescaped control character') }
		if byte != `\\` {
			out << byte
			continue
		}
		if reader.position == reader.bytes.len { return json_failure('Truncated JSON escape') }
		escape := reader.bytes[reader.position]
		reader.position++
		match escape {
			`"`, `\\`, `/` { out << escape }
			`b` { out << u8(8) }
			`f` { out << u8(12) }
			`n` { out << u8(10) }
			`r` { out << u8(13) }
			`t` { out << u8(9) }
			`u` {
				mut code := reader.hex()!
				if code >= 0xd800 && code <= 0xdbff {
					if !reader.take(`\\`) || !reader.take(`u`) {
						return json_failure('Missing Unicode surrogate')
					}
					low := reader.hex()!
					if low < 0xdc00 || low > 0xdfff {
						return json_failure('Invalid Unicode surrogate')
					}
					code = 0x10000 + ((code - 0xd800) << 10) + low - 0xdc00
				}
				json_utf8(mut out, code)!
			}
			else { return json_failure('Invalid JSON escape') }
		}
	}
	return json_failure('Unterminated JSON string')
}

fn (mut reader JsonReader) numeric() !u64 {
	start := reader.position
	negative := reader.take(`-`)
	if reader.position == reader.bytes.len { return json_failure('Missing JSON number') }
	if !reader.take(`0`) {
		if reader.bytes[reader.position] < `1` || reader.bytes[reader.position] > `9` {
			return json_failure('Invalid JSON number')
		}
		for reader.position < reader.bytes.len && reader.bytes[reader.position] >= `0` && reader.bytes[reader.position] <= `9` {
			reader.position++
		}
	}
	mut real := false
	if reader.take(`.`) {
		real = true
		digits := reader.position
		for reader.position < reader.bytes.len && reader.bytes[reader.position] >= `0` && reader.bytes[reader.position] <= `9` {
			reader.position++
		}
		if reader.position == digits { return json_failure('Missing fractional digits') }
	}
	if reader.take(`e`) || reader.take(`E`) {
		real = true
		if !reader.take(`+`) { reader.take(`-`) }
		digits := reader.position
		for reader.position < reader.bytes.len && reader.bytes[reader.position] >= `0` && reader.bytes[reader.position] <= `9` {
			reader.position++
		}
		if reader.position == digits { return json_failure('Missing exponent digits') }
	}
	if real {
		length := reader.position - start
		if length > 128 { return json_failure('JSON decimal precision profile exceeded') }
		mut significant := 0
		for i in start .. reader.position {
			if reader.bytes[i] in [u8(`e`), `E`]! { break }
			if json_digit(reader.bytes[i]) && (significant != 0 || reader.bytes[i] != `0`) {
				significant++
			}
		}
		// Longer mantissas require Foundation's decimal-number storage rather
		// than silently rounding them into this binary-double profile.
		if significant > 17 { return json_failure('JSON decimal precision profile exceeded') }
		mut token := [129]u8{}
		unsafe { C.memcpy(&token[0], voidptr(u64(reader.bytes.data) + u64(start)), usize(length)) }
		value := C.strtod(unsafe { &char(&token[0]) }, unsafe { nil })
		if !math.is_finite(value) { return json_failure('Non-finite JSON number') }
		object := objc_allocate(ios_runtime.names['NSNumber'])
		mut header := obj_header(object)
		header.is_real = true
		header.real_number = value
		return object
	}
	mut magnitude := u64(0)
	for i := start + int(negative); i < reader.position; i++ {
		digit := u64(reader.bytes[i] - `0`)
		if magnitude > (u64(-1) - digit) / 10 {
			return json_failure('JSON integer exceeds 64-bit profile')
		}
		magnitude = magnitude * 10 + digit
	}
	if negative && magnitude > u64(1) << 63 {
		return json_failure('JSON integer exceeds signed 64-bit profile')
	}
	object := objc_allocate(ios_runtime.names['NSNumber'])
	mut header := obj_header(object)
	if negative {
		header.number = if magnitude == u64(1) << 63 {
			i64(-9223372036854775807) - 1
		} else {
			-i64(magnitude)
		}
	} else {
		header.number = i64(magnitude)
		header.unsigned_number = magnitude > u64(9223372036854775807)
	}
	return object
}

fn (mut reader JsonReader) value(depth int) !u64 {
	if depth > json_depth_limit || reader.nodes == 65536 {
		return json_failure('JSON nesting or node limit exceeded')
	}
	reader.nodes++
	reader.whitespace()
	if reader.position == reader.bytes.len { return json_failure('Unexpected end of JSON') }
	byte := reader.bytes[reader.position]
	if byte == `"` { return reader.text()! }
	if byte == `-` || (byte >= `0` && byte <= `9`) { return reader.numeric()! }
	if reader.literal('null') { return objc_retain(json_null()) }
	if reader.literal('true') { return objc_retain(framework_object('_kCFBooleanTrue')) }
	if reader.literal('false') { return objc_retain(framework_object('_kCFBooleanFalse')) }
	if byte != `[` && byte != `{` { return json_failure('Unexpected JSON token') }
	reader.position++
	dictionary := byte == `{`
	name := if dictionary {
		if reader.options & 1 != 0 { 'NSMutableDictionary' } else { 'NSDictionary' }
	} else {
		if reader.options & 1 != 0 { 'NSMutableArray' } else { 'NSArray' }
	}
	object := objc_allocate(ios_runtime.names[name])
	mut header := obj_header(object)
	header.json_immutable = reader.options & 1 == 0
	mut complete := false
	defer { if !complete { objc_release(object) } }
	close := if dictionary { u8(`}`) } else { u8(`]`) }
	for {
		reader.whitespace()
		if reader.take(close) {
			complete = true
			return object
		}
		mut key := u64(0)
		if dictionary {
			key = reader.text()!
			reader.whitespace()
			if !reader.take(`:`) {
				objc_release(key)
				return json_failure('Missing JSON colon')
			}
		}
		item := reader.value(depth + 1) or {
			objc_release(key)
			return err
		}
		position := if dictionary { dictionary_index(header, key) } else { -1 }
		if !dictionary || position < 0 {
			if dictionary { header.keys << objc_retain(key) }
			array_append(mut header, item)
		} else if reader.options & 1 != 0 {
			objc_store_strong(unsafe { &header.items[position] }, item)
		}
		objc_release(key)
		objc_release(item)
		reader.whitespace()
		if reader.take(close) {
			complete = true
			return object
		}
		if !reader.take(`,`) { return json_failure('Missing JSON comma') }
		// Foundation accepts one trailing comma, including without JSON5.
	}
	return json_failure('Unreachable JSON parser state')
}

fn json_read(data u64, options u64) !u64 {
	if options & ~u64(5) != 0 {
		return json_failure('Mutable JSON leaves and extended reading options are not implemented')
	}
	if !objc_is_kind(data, ios_runtime.names['NSData']) {
		return json_failure('JSON input must be NSData')
	}
	length := data_length(data)
	if length > json_size_limit { return json_failure('JSON input exceeds size limit') }
	bytes := unsafe { (&u8(data_pointer(data))).vbytes(int(length)) }
	input := json_input(bytes)!
	defer { if input.owned { unsafe { input.bytes.free() } } }
	mut reader := JsonReader{ bytes: input.bytes, options: options }
	object := reader.value(0)!
	reader.whitespace()
	if reader.position != reader.bytes.len {
		objc_release(object)
		return json_failure('Trailing JSON data')
	}
	if options & 4 == 0 && !objc_is_kind(object, ios_runtime.names['NSArray']) && !objc_is_kind(object, ios_runtime.names['NSDictionary']) {
		objc_release(object)
		return json_failure('JSON fragments require the fragments option')
	}
	return object
}
