// SPDX-License-Identifier: GPL-2.0-or-later
module runtimehost

import androidhost as ah
import androidrun
import json2

fn any_value(value json2.Any) !ah.Value {
	return androidrun.load_json(json2.encode(value))!
}

// Filesystem bytes use surrogateescape; valid UTF-8 stays unchanged. In
// particular a byte sequence encoding a surrogate is not valid filesystem
// UTF-8 and must escape each of its bytes separately.
fn filesystem_text(value string) string {
	mut result := []u8{}
	mut position := 0
	for position < value.len {
		first := value[position]
		width := if first < 0x80 {
			1
		} else if first in u8(0xc2) .. u8(0xe0) {
			2
		} else if first in u8(0xe0) .. u8(0xf0) {
			3
		} else if first in u8(0xf0) .. u8(0xf5) {
			4
		} else {
			0
		}
		mut valid := width != 0 && position + width <= value.len
		if valid && width > 1 {
			for next in 1 .. width { if value[position + next] & 0xc0 != 0x80 { valid = false } }
			second := value[position + 1]
			if (first == 0xe0 && second < 0xa0) || (first == 0xed && second >= 0xa0) || (first == 0xf0 && second < 0x90) || (first == 0xf4 && second >= 0x90) {
				valid = false
			}
		}
		if valid {
			result << value[position..position + width].bytes()
			position += width
		} else {
			result << rune(0xdc00 + u32(first)).str().bytes()
			position++
		}
	}
	return result.bytestr()
}

fn native_quote(value string) string { return androidrun.dump_json(ah.Value(value), -1) }

fn native_dump_at(value json2.Any, sorted bool, pretty bool, depth int) string {
	if value is string { return native_quote(value) }
	pad := '  '.repeat(depth + 1)
	ending := '  '.repeat(depth)
	if value is map[string]json2.Any {
		mut keys := value.keys()
		if sorted { keys.sort() }
		mut rows := []string{}
		for key in keys {
			rows << (if pretty { pad } else { '' }) + native_quote(key) + ': ' + native_dump_at(value[key] or { json2.Null{} }, sorted, pretty, depth + 1)
		}
		if rows.len == 0 { return '{}' }
		return if pretty {
			'{\n' + rows.join(',\n') + '\n' + ending + '}'
		} else {
			'{' + rows.join(', ') + '}'
		}
	}
	if value is []json2.Any {
		mut rows := []string{}
		for item in value {
			rows << (if pretty { pad } else { '' }) + native_dump_at(item, sorted, pretty, depth + 1)
		}
		if rows.len == 0 { return '[]' }
		return if pretty {
			'[\n' + rows.join(',\n') + '\n' + ending + ']'
		} else {
			'[' + rows.join(', ') + ']'
		}
	}
	return json2.encode(value)
}
