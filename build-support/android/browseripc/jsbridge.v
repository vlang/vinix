// SPDX-License-Identifier: GPL-2.0-or-later
module browseripc

import encoding.binary

// WebView.addJavascriptInterface objects, as exposed to page JavaScript.
//
// js_interfaces (client to engine) replaces a view's interface list. Its text
// has one line per interface: the JavaScript name, then the names of the
// methods Java annotated with @JavascriptInterface, separated by spaces. An
// empty payload removes every interface. Like Android, changes apply to the
// next page load.
//
// js_call (engine to client) is a synchronous call from page JavaScript: an
// eight-byte call id, then "interface\nmethod\narguments". js_reply (client to
// engine) answers it: the call id, a status byte (0 value, 1 exception), then
// one tagged value (void is "1:u") or the exception message. Values and arguments
// use the tagged text encoding of tagged_list; neither side parses JSON.
pub const max_js_interfaces = 16
pub const max_js_methods = 256
pub const max_js_arguments = 32

pub struct JsInterface {
pub:
	name    string
	methods []string
}

pub struct JsCall {
pub:
	id        u64
	iface     string
	method    string
	arguments string
}

pub fn js_identifier(name string) bool {
	if name.len == 0 || name.len > 128 {
		return false
	}
	for i, c in name {
		letter := (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || c == `_` || c == `$`
		if !letter && (i == 0 || c < `0` || c > `9`) {
			return false
		}
	}
	return true
}

pub fn parse_js_interfaces(bytes []u8) ![]JsInterface {
	text(bytes, 64 * 1024, true)!
	mut result := []JsInterface{}
	if bytes.len == 0 {
		return result
	}
	for line in bytes.bytestr().split('\n') {
		words := line.split(' ')
		if words.len < 2 || words.len - 1 > max_js_methods || result.len == max_js_interfaces {
			return error('invalid browser JavaScript interface list')
		}
		for word in words {
			if !js_identifier(word) {
				return error('invalid browser JavaScript identifier')
			}
		}
		for existing in result {
			if existing.name == words[0] {
				return error('duplicate browser JavaScript interface')
			}
		}
		result << JsInterface{
			name:    words[0]
			methods: words[1..]
		}
	}
	return result
}

pub fn parse_js_call(bytes []u8) !JsCall {
	if bytes.len < 8 || binary.little_endian_u64(bytes[..8]) == 0 {
		return error('invalid browser JavaScript call identity')
	}
	text(bytes[8..], max_text, false)!
	parts := bytes[8..].bytestr().split_nth('\n', 3)
	if parts.len != 3 || !js_identifier(parts[0]) || !js_identifier(parts[1]) {
		return error('invalid browser JavaScript call target')
	}
	tagged_list(parts[2], max_js_arguments)!
	return JsCall{
		id:        binary.little_endian_u64(bytes[..8])
		iface:     parts[0]
		method:    parts[1]
		arguments: parts[2]
	}
}

// Tagged text: each value is a decimal character length, a colon, then that
// many characters starting with a tag: s string, n number, b boolean (b0/b1),
// z null, u undefined. A list is values concatenated. Lengths count UTF-16
// code units, as JavaScript and Java strings do.
pub fn tagged_list(list string, limit int) ! {
	runes := list.runes()
	mut position := 0
	mut count := 0
	for position < runes.len {
		mut length := 0
		mut digits := 0
		for position < runes.len && runes[position] >= `0` && runes[position] <= `9` {
			length = length * 10 + int(runes[position] - `0`)
			position++
			digits++
			if digits > 8 {
				return error('browser JavaScript value too long')
			}
		}
		if digits == 0 || length == 0 || position + 1 >= runes.len || runes[position] != `:`
			|| runes[position + 1] !in [`s`, `n`, `b`, `z`, `u`] {
			return error('invalid browser JavaScript value')
		}
		position++
		// The length counts UTF-16 code units of the tag and data.
		mut used := 0
		for used < length && position < runes.len {
			used += if runes[position] > 0xffff { 2 } else { 1 }
			position++
		}
		if used != length {
			return error('truncated browser JavaScript value')
		}
		count++
		if count > limit {
			return error('too many browser JavaScript values')
		}
	}
}
