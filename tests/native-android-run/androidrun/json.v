// SPDX-License-Identifier: GPL-2.0-or-later
module androidrun

import androidhost as ah
import hosttest
import json2
import strconv

struct JsonReader {
	data string
mut:
	position int
}

fn (mut reader JsonReader) space() {
	for reader.position < reader.data.len && reader.data[reader.position] in [u8(` `), `\n`, `\r`,
		`\t`] {
		reader.position++
	}
}

fn (mut reader JsonReader) expect(byte u8) ! {
	reader.space()
	if reader.position >= reader.data.len || reader.data[reader.position] != byte {
		return error('invalid JSON delimiter at byte ' + reader.position.str())
	}
	reader.position++
}

fn (mut reader JsonReader) string_value() !string {
	reader.expect(`"`)!
	mut bytes := []u8{}
	for reader.position < reader.data.len {
		byte := reader.data[reader.position]
		reader.position++
		if byte == `"` { return bytes.bytestr() }
		if byte < 32 { return error('invalid JSON control character') }
		if byte != `\\` {
			bytes << byte
			continue
		}
		if reader.position == reader.data.len { return error('incomplete JSON escape') }
		escape := reader.data[reader.position]
		reader.position++
		match escape {
			`"`, `\\`, `/` { bytes << escape }
			`b` { bytes << u8(8) }
			`f` { bytes << u8(12) }
			`n` { bytes << u8(10) }
			`r` { bytes << u8(13) }
			`t` { bytes << u8(9) }
			`u` {
				if reader.position + 4 > reader.data.len {
					return error('incomplete JSON Unicode escape')
				}
				mut code := json_hex(reader.data[reader.position..reader.position + 4])!
				reader.position += 4
				if code >= 0xd800 && code <= 0xdbff && reader.position + 6 <= reader.data.len && reader.data[reader.position..].starts_with('\\u') {
					low := json_hex(reader.data[reader.position + 2..reader.position + 6]) or { u64(0) }
					if low >= 0xdc00 && low <= 0xdfff {
						code = 0x10000 + (code - 0xd800) * 1024 + low - 0xdc00
						reader.position += 6
					}
				}
				// Lone UTF-16 surrogates remain owned WTF-8 until a strict text
				// boundary, matching the existing tagged metadata transport.
				bytes << rune(code).str().bytes()
			}
			else { return error('invalid JSON escape') }
		}
	}
	return error('unterminated JSON string')
}

fn json_hex(value string) !u64 {
	if value.len != 4 || !value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`) || (it >= `A` && it <= `F`)) {
		return error('invalid JSON Unicode escape')
	}
	return strconv.parse_uint(value, 16, 16)!
}

fn (mut reader JsonReader) value(depth int) !ah.Value {
	if depth >= 1000 { return error('JSON nesting limit exceeded') }
	reader.space()
	if reader.position == reader.data.len { return error('missing JSON value') }
	match reader.data[reader.position] {
		`"` { return ah.Value(reader.string_value()!) }
		`[` {
			reader.position++
			reader.space()
			mut values := []ah.Value{}
			if reader.position < reader.data.len && reader.data[reader.position] == `]` {
				reader.position++
				return ah.Value(values)
			}
			for {
				values << reader.value(depth + 1)!
				reader.space()
				if reader.position < reader.data.len && reader.data[reader.position] == `]` {
					reader.position++
					break
				}
				reader.expect(`,`)!
			}
			return ah.Value(values)
		}
		`{` {
			reader.position++
			reader.space()
			mut values := map[string]ah.Value{}
			if reader.position < reader.data.len && reader.data[reader.position] == `}` {
				reader.position++
				return ah.Value(values)
			}
			for {
				key := reader.string_value()!
				reader.expect(`:`)!
				values[key] = reader.value(depth + 1)!
				reader.space()
				if reader.position < reader.data.len && reader.data[reader.position] == `}` {
					reader.position++
					break
				}
				reader.expect(`,`)!
			}
			return ah.Value(values)
		}
		else {}
	}
	for token, value in {
		'null':      ah.Value(json2.Null{})
		'true':      ah.Value(true)
		'false':     ah.Value(false)
		'NaN':       ah.Value(ah.Number{'nan'})
		'Infinity':  ah.Value(ah.Number{'inf'})
		'-Infinity': ah.Value(ah.Number{'-inf'})
	} {
		if reader.data[reader.position..].starts_with(token) {
			reader.position += token.len
			return value
		}
	}
	start := reader.position
	if reader.data[reader.position] == `-` { reader.position++ }
	if reader.position == reader.data.len { return error('invalid JSON number') }
	if reader.data[reader.position] == `0` {
		reader.position++
	} else {
		if reader.data[reader.position] < `1` || reader.data[reader.position] > `9` {
			return error('invalid JSON number')
		}
		for reader.position < reader.data.len && reader.data[reader.position].is_digit() {
			reader.position++
		}
	}
	if reader.position < reader.data.len && reader.data[reader.position] == `.` {
		reader.position++
		digits := reader.position
		for reader.position < reader.data.len && reader.data[reader.position].is_digit() {
			reader.position++
		}
		if reader.position == digits { return error('invalid JSON fraction') }
	}
	if reader.position < reader.data.len && reader.data[reader.position] in [u8(`e`), `E`] {
		reader.position++
		if reader.position < reader.data.len && reader.data[reader.position] in [
			u8(`+`),
			`-`,
		] {
			reader.position++
		}
		digits := reader.position
		for reader.position < reader.data.len && reader.data[reader.position].is_digit() {
			reader.position++
		}
		if reader.position == digits { return error('invalid JSON exponent') }
	}
	return ah.Value(ah.Number{reader.data[start..reader.position]})
}

pub fn load_json(data string) !ah.Value {
	hosttest.module_decode_utf8(data)!
	mut reader := JsonReader{ data: data }
	value := reader.value(0)!
	reader.space()
	if reader.position != data.len {
		return error('extra JSON data at byte ' + reader.position.str())
	}
	return value
}

fn hex4(value u32) string {
	digits := value.hex()
	return '0'.repeat(4 - digits.len) + digits
}

fn wtf8_points(value string) []rune {
	mut points := []rune{}
	mut position := 0
	for position < value.len {
		first := value[position]
		width := if first < 0x80 {
			1
		} else if first >= 0xc2 && first <= 0xdf {
			2
		} else if first >= 0xe0 && first <= 0xef {
			3
		} else if first >= 0xf0 && first <= 0xf4 {
			4
		} else {
			0
		}
		if width == 0 || position + width > value.len {
			points << rune(0xfffd)
			position++
			continue
		}
		mut point := u32(first & if width == 1 {
			u8(0x7f)
		} else if width == 2 {
			u8(0x1f)
		} else if width == 3 {
			u8(0xf)
		} else {
			u8(7)
		})
		mut valid := true
		for index in 1 .. width {
			byte := value[position + index]
			if byte < 0x80 || byte > 0xbf {
				valid = false
				break
			}
			point = point * 64 + u32(byte & 0x3f)
		}
		if valid {
			points << rune(point)
			position += width
		} else {
			points << rune(0xfffd)
			position++
		}
	}
	return points
}

fn quote_json(value string) string {
	mut bytes := []u8{}
	bytes << `"`
	for point in wtf8_points(value) {
		match point {
			`"` { bytes << '\\"'.bytes() }
			`\\` { bytes << '\\\\'.bytes() }
			`\n` { bytes << '\\n'.bytes() }
			`\r` { bytes << '\\r'.bytes() }
			`\t` { bytes << '\\t'.bytes() }
			8 { bytes << '\\b'.bytes() }
			12 { bytes << '\\f'.bytes() }
			else {
				if point >= 32 && point <= 126 {
					bytes << u8(point)
				} else if point <= 0xffff {
					bytes << ('\\u' + hex4(u32(point))).bytes()
				} else {
					scalar := u32(point) - 0x10000
					bytes << ('\\u' + hex4(0xd800 + scalar / 1024) + '\\u' + hex4(0xdc00 + scalar % 1024)).bytes()
				}
			}
		}
	}
	bytes << `"`
	return bytes.bytestr()
}

fn dump_at(value ah.Value, indent int, depth int) string {
	return match value {
		string { quote_json(value) }
		ah.Number {
			match value.text {
				'nan' { 'NaN' }
				'inf' { 'Infinity' }
				'-inf' { '-Infinity' }
				else { value.text }
			}
		}
		[]ah.Value {
			items := value.map(dump_at(it, indent, depth + 1))
			if items.len == 0 {
				'[]'
			} else if indent < 0 {
				'[' + items.join(', ') + ']'
			} else {
				'[\n' + ' '.repeat(indent * (depth + 1)) + items.join(',\n' + ' '.repeat(indent * (depth + 1))) + '\n' + ' '.repeat(indent * depth) + ']'
			}
		}
		map[string]ah.Value {
			mut items := []string{}
			for key, item in value {
				items << quote_json(key) + ': ' + dump_at(item, indent, depth + 1)
			}
			if items.len == 0 {
				'{}'
			} else if indent < 0 {
				'{' + items.join(', ') + '}'
			} else {
				'{\n' + ' '.repeat(indent * (depth + 1)) + items.join(',\n' + ' '.repeat(indent * (depth + 1))) + '\n' + ' '.repeat(indent * depth) + '}'
			}
		}
		else { ah.encode(value) }
	}
}

pub fn dump_json(value ah.Value, indent int) string { return dump_at(value, indent, 0) }
