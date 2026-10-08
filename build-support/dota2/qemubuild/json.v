// SPDX-License-Identifier: GPL-2.0-or-later
module qemubuild

import json2
import strconv

fn hex4(value u32) string {
	text := strconv.format_uint(u64(value), 16)
	return '0'.repeat(4 - text.len) + text
}

fn quoted(text string) string {
	mut result := '"'
	for ch in text.runes() {
		result += match ch {
			`"` { '\\"' }
			`\\` { '\\\\' }
			`\b` { '\\b' }
			`\f` { '\\f' }
			`\n` { '\\n' }
			`\r` { '\\r' }
			`\t` { '\\t' }
			else {
				if ch < 32 || ch >= 127 {
					if ch > 0xffff {
						value := u32(ch) - 0x10000
						'\\u' + hex4(0xd800 + (value >> 10)) + '\\u' + hex4(0xdc00 + (value & 0x3ff))
					} else {
						'\\u' + hex4(u32(ch))
					}
				} else {
					ch.str()
				}
			}
		}
	}
	return result + '"'
}

// The cache schema retains Python json.dumps' separators, ASCII quoting and
// optional key ordering. The manifest retains its original insertion order.
pub fn dumps(value json2.Any, sorted bool, pretty bool) string {
	return dump_at(value, sorted, pretty, 0)
}

fn dump_at(value json2.Any, sorted bool, pretty bool, depth int) string {
	pad := '  '.repeat(depth + 1)
	end := '  '.repeat(depth)
	if value is map[string]json2.Any {
		mut keys := value.keys()
		if sorted { keys.sort() }
		mut fields := []string{}
		for key in keys {
			fields << (if pretty { pad } else { '' }) + quoted(key) +
				': ' + dump_at(value[key] or { json2.Null{} }, sorted, pretty, depth + 1)
		}
		if fields.len == 0 { return '{}' }
		return if pretty {
			'{\n' + fields.join(',\n') + '\n' + end + '}'
		} else {
			'{' + fields.join(', ') + '}'
		}
	}
	if value is []json2.Any {
		mut fields := []string{}
		for item in value {
			fields << (if pretty { pad } else { '' }) + dump_at(item, sorted, pretty, depth + 1)
		}
		if fields.len == 0 { return '[]' }
		return if pretty {
			'[\n' + fields.join(',\n') + '\n' + end + ']'
		} else {
			'[' + fields.join(', ') + ']'
		}
	}
	if value is string { return quoted(value) }
	return json2.encode(value)
}
