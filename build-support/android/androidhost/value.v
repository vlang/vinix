module androidhost

import json2
import strconv

// Preserve JSON integer spelling and width for Python's strict manifest checks.
pub struct Number {
pub mut:
	text string
}

pub fn (mut n Number) from_json_number(text string) ! { n.text = text }

pub fn (n Number) to_json() string { return n.text }

pub type Value = Number | []Value | bool | int | i64 | u64 | string | map[string]Value | json2.Null

pub fn (v Value) object() map[string]Value {
	if v is map[string]Value { return v }
	return map[string]Value{}
}

pub fn (v Value) items() []Value {
	if v is []Value { return v }
	return []Value{}
}

pub fn (v Value) text() string {
	if v is string { return v }
	return ''
}

pub fn field(row map[string]Value, name string) Value { return row[name] or { Value(json2.null) } }

pub fn integer(v Value) ?u64 {
	return match v {
		Number {
			if v.text.contains_any('.eE-') { return none }
			strconv.parse_uint(v.text, 10, 64) or { return none }
		}
		int, i64 {
			if v < 0 { return none }
			u64(v)
		}
		u64 { v }
		else { none }
	}
}

pub fn encode(v Value) string {
	return match v {
		Number { v.text }
		json2.Null { 'null' }
		[]Value { '[' + v.map(encode(it)).join(',') + ']' }
		map[string]Value {
			mut rows := []string{}
			for name, item in v { rows << json2.encode(name) + ':' + encode(item) }
			'{' + rows.join(',') + '}'
		}
		else { json2.encode(v) }
	}
}
