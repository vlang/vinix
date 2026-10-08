// SPDX-License-Identifier: BSD-2-Clause
module fixturehost

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

fn pretty(value json2.Any, depth int) string {
	indent := '  '.repeat(depth)
	next_indent := indent + '  '
	return match value {
		map[string]json2.Any {
			if value.len == 0 {
				'{}'
			} else {
				mut rows := []string{}
				for name, item in value {
					rows << next_indent + quoted(name) + ': ' + pretty(item, depth + 1)
				}
				'{\n' + rows.join(',\n') + '\n' + indent + '}'
			}
		}
		[]json2.Any {
			if value.len == 0 {
				'[]'
			} else {
				'[\n' + value.map(next_indent + pretty(it, depth + 1)).join(',\n') + '\n' + indent + ']'
			}
		}
		string { quoted(value) }
		else { json2.encode(value) }
	}
}

fn json_strings(values []string) json2.Any { return json2.Any(values.map(json2.Any(it))) }

fn write_schema(path string, value json2.Any) ! { write(path, pretty(value, 0) + '\n')! }
