// SPDX-License-Identifier: GPL-2.0-or-later
module perfreport

import json2

// Emit numeric tokens as scalars, including arbitrary-width transcript rounds.
pub fn encode(item Value, pretty bool) string { return encode_depth(item, pretty, 0) }

fn encode_depth(item Value, pretty bool, depth int) string {
	match item {
		Number {
			return match item.text {
				'nan' { 'NaN' }
				'inf' { 'Infinity' }
				'-inf' { '-Infinity' }
				else { item.text }
			}
		}
		string { return json2.encode(item, escape_unicode: true) }
		bool { return if item { 'true' } else { 'false' } }
		json2.Null { return 'null' }
		[]Value {
			if item.len == 0 { return '[]' }
			parts := item.map(encode_depth(it, pretty, depth + 1))
			if !pretty { return '[' + parts.join(',') + ']' }
			prefix := '  '.repeat(depth + 1)
			return '[\n' + prefix + parts.join(',\n' + prefix) + '\n' + '  '.repeat(depth) + ']'
		}
		map[string]Value {
			if item.len == 0 { return '{}' }
			mut parts := []string{}
			for key, entry in item {
				parts << json2.encode(key, escape_unicode: true) + if pretty { ': ' } else { ':' } + encode_depth(entry, pretty, depth + 1)
			}
			if !pretty { return '{' + parts.join(',') + '}' }
			prefix := '  '.repeat(depth + 1)
			return '{\n' + prefix + parts.join(',\n' + prefix) + '\n' + '  '.repeat(depth) + '}'
		}
	}
}

pub fn (verdict Verdict) to_value() Value {
	return Value(map[string]Value{
		'rows':    Value(verdict.rows.map(Value(it)))
		'reports': Value(verdict.reports.map(Value(it)))
		'errors':  Value(verdict.errors.map(Value(it)))
	})
}
