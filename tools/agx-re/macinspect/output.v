module macinspect

import traceanalysis as j
import json2
import strings

fn quoted_json(s string) string {
	mut output := strings.new_builder(s.len + 2)
	output.write_u8(`"`)
	for r in s.runes() {
		match r {
			`"` { output.write_string('\\"') }
			`\\` { output.write_string('\\\\') }
			`\b` { output.write_string('\\b') }
			`\f` { output.write_string('\\f') }
			`\n` { output.write_string('\\n') }
			`\r` { output.write_string('\\r') }
			`\t` { output.write_string('\\t') }
			else {
				if r < 32 || r >= 127 {
					if r <= 0xffff {
						output.write_string('\\u${u32(r):04x}')
					} else {
						code := u32(r) - 0x10000
						output.write_string('\\u${0xd800 + (code >> 10):04x}\\u${0xdc00 + (code & 0x3ff):04x}')
					}
				} else {
					output.write_u8(u8(r))
				}
			}
		}
	}
	output.write_u8(`"`)
	return output.str()
}

fn encode_depth(item j.Value, compact bool, depth int) !string {
	return match item {
		json2.Null { 'null' }
		bool {
			if item { 'true' } else { 'false' }
		}
		string { quoted_json(item) }
		j.Number {
			if item.text in ['NaN', 'Infinity', '-Infinity'] {
				item.text
			} else {
				j.string_value(item)
			}
		}
		int, i64, u8, u32, u64 { item.str() }
		[]j.Value {
			mut entries := []string{}
			for child in item { entries << encode_depth(child, compact, depth + 1)! }
			if compact || entries.len == 0 {
				'[' + entries.join(', ') + ']'
			} else {
				padding := '  '.repeat(depth + 1)
				'[\n' + padding + entries.join(',\n' + padding) + '\n' + '  '.repeat(depth) + ']'
			}
		}
		map[string]j.Value {
			if item.len == 1 && '__vinix_binary' in item {
				return error('Object of type bytes is not JSON serializable')
			}
			if item.len == 1 && '__vinix_opaque' in item {
				return error('Object of type ${j.string_value(value(item, '__vinix_opaque'))} is not JSON serializable')
			}
			mut keys := item.keys()
			keys.sort()
			mut entries := []string{}
			for key in keys {
				entries << quoted_json(key) + ': ' + encode_depth(value(item, key), compact, depth + 1)!
			}
			if compact || entries.len == 0 {
				'{' + entries.join(', ') + '}'
			} else {
				padding := '  '.repeat(depth + 1)
				'{\n' + padding + entries.join(',\n' + padding) + '\n' + '  '.repeat(depth) + '}'
			}
		}
	}
}

pub fn encode_manifest(manifest j.Value, compact bool) !string {
	return encode_depth(manifest, compact, 0)
}
