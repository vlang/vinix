// SPDX-License-Identifier: GPL-2.0-or-later
module muslnative

import json2

// Existing cache directories use the original sorted JSON with ASCII escapes,
// comma-space and colon-space separators. Preserve that byte identity.
fn quote(text string) string {
	mut result := '"'
	for c in text.runes() {
		match c {
			`"` { result += '\\"' }
			`\\` { result += '\\\\' }
			`\b` { result += '\\b' }
			`\f` { result += '\\f' }
			`\n` { result += '\\n' }
			`\r` { result += '\\r' }
			`\t` { result += '\\t' }
			else {
				if c < 32 || c > 126 {
					if c <= 65535 {
						result += '\\u${int(c):04x}'
					} else {
						number := int(c) - 65536
						result += '\\u${0xd800 + (number >> 10):04x}\\u${0xdc00 + (number & 1023):04x}'
					}
				} else {
					result += c.str()
				}
			}
		}
	}
	return result + '"'
}

pub fn canonical(data json2.Any) !string {
	return match data {
		string { quote(data) }
		bool {
			if data { 'true' } else { 'false' }
		}
		i64 { data.str() }
		u64 { data.str() }
		int { data.str() }
		[]json2.Any {
			mut items := []string{}
			for item in data { items << canonical(item)! }
			'[' + items.join(', ') + ']'
		}
		map[string]json2.Any {
			mut keys := data.keys()
			keys.sort()
			mut items := []string{}
			for key in keys { items << quote(key) + ': ' + canonical(data[key]!)! }
			'{' + items.join(', ') + '}'
		}
		else { return error('unsupported musl cache-key value') }
	}
}
