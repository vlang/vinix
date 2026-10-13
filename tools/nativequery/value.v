// SPDX-License-Identifier: GPL-2.0-or-later
module nativequery

import json2
import strconv

pub struct Number {
pub mut:
	text string
}

pub fn (mut number Number) from_json_number(text string) ! { number.text = text }

pub fn (number Number) to_json() string { return number.text }

// JSON callbacks keep raw numeric tokens. File/device identities and native
// integer results can exceed the signed 64-bit range and must not become floats.
pub type Value = Number | []Value | bool | int | i64 | u64 | string | map[string]Value | json2.Null

pub fn (value Value) as_array() []Value {
	return match value {
		[]Value { value }
		else { []Value{} }
	}
}

pub fn (value Value) as_map() map[string]Value {
	return match value {
		map[string]Value { value }
		else { map[string]Value{} }
	}
}

pub fn (value Value) str() string {
	return match value {
		Number { value.text }
		string { value }
		else { json2.encode(value) }
	}
}

pub fn (value Value) i64() i64 { return strconv.parse_int(value.str(), 10, 64) or { 0 } }

pub fn (value Value) u64() u64 { return strconv.parse_uint(value.str(), 10, 64) or { 0 } }

pub fn (value Value) int() int { return int(value.i64()) }

fn binding_index(value Value) !int {
	raw := match value {
		Number { value.text }
		int, i64, u64 { value.str() }
		else { return error('invalid native callback error index type') }
	}
	if raw.contains_any('.eE') { return error('invalid native callback error index') }
	return int(strconv.common_parse_int(raw, 10, 64, true, true)!)
}

pub fn encode(value Value) string {
	return match value {
		Number { value.text }
		json2.Null { 'null' }
		[]Value { '[' + value.map(encode(it)).join(',') + ']' }
		map[string]Value {
			mut fields := []string{}
			for name, item in value { fields << json2.encode(name) + ':' + encode(item) }
			'{' + fields.join(',') + '}'
		}
		else { json2.encode(value) }
	}
}
