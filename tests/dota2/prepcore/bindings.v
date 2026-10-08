// SPDX-License-Identifier: GPL-2.0-or-later
module prepcore

import encoding.hex
import hosttest
import json2
import os

pub struct BindingError {
pub:
	value map[string]json2.Any
}

pub fn (e BindingError) msg() string {
	return decode(e.value['message'] or { json2.Any('') }.str()) or { 'Dota primitive failed' }
}

pub fn (e BindingError) code() int { return 0 }

pub struct PrepareError {
pub:
	message string
}

pub fn (e PrepareError) msg() string { return e.message }

pub fn (e PrepareError) code() int { return 0 }

fn failed(message string) IError { return PrepareError{message} }

fn decode(value string) !string { return hex.decode(value)!.bytestr() }

fn encoded(values []string) json2.Any { return json2.Any(values.map(json2.Any(it.bytes().hex()))) }

fn callback(operation string, arguments map[string]json2.Any) !json2.Any {
	println(json2.encode({
		'callback':  json2.Any(operation)
		'arguments': json2.Any(arguments)
	}, escape_unicode: true))
	row := hosttest.decode_json(os.get_raw_line())!.as_map()
	if 'error' in row { return BindingError{row['error']!.as_map()} }
	return row['value']!
}

fn primitive(operation string, values []string) !json2.Any {
	return callback(operation, {
		'args': encoded(values)
	})!
}

fn path(function string, values []string) !string {
	return decode(callback('path', {
		'function': json2.Any(function)
		'args':     encoded(values)
	})!.str())!
}

fn join(parent string, children ...string) !string {
	return path('joinpath', [parent, ...children])!
}

fn parent(value string) !string { return path('parent', [value])! }

fn test(function string, value string) !bool {
	return callback('test', {
		'function': json2.Any(function)
		'args':     encoded([value])
	})!.bool()
}

fn remove_existing(value string) ! {
	if test('exists', value)! || test('is_symlink', value)! { primitive('unlink', [value])! }
}

fn mkdir(value string) ! {
	callback('mkdir', {
		'args':     encoded([value])
		'parents':  json2.Any(true)
		'exist_ok': json2.Any(true)
	})!
}

fn listing(function string, values []string) ![]string {
	return callback('list', {
		'function': json2.Any(function)
		'args':     encoded(values)
	})!.as_array().map(decode(it.str())!)
}

fn read(value string, limit int) ![]u8 {
	return hex.decode(callback('read', {
		'args':  encoded([value])
		'limit': json2.Any(limit)
	})!.str())!
}

fn text(value string) !string { return decode(primitive('read_text', [value])!.str())! }

fn attribute(name string) !json2.Any {
	return callback('attribute', {
		'name': json2.Any(name)
	})!
}

fn field(name string) !string { return decode(attribute(name)!.str())! }

fn fields(name string) ![]string { return attribute(name)!.as_array().map(decode(it.str())!) }

fn checked(argv []string) ! {
	callback('run', {
		'args':  encoded(argv)
		'check': json2.Any(true)
	})!
}

fn output(argv []string) !string {
	return decode(callback('output', {
		'args': encoded(argv)
		'text': json2.Any(true)
	})!.str())!
}

fn needed(value string) ![]string {
	return callback('regex', {
		'args':     encoded([r'\(NEEDED\).*\[([^]]+)\]', value])
		'function': json2.Any('findall')
	})!.as_array().map(decode(it.str())!)
}

fn quote(value string) !string { return decode(primitive('quote', [value])!.str())! }

fn chmod(value string, mode int) ! {
	callback('chmod', {
		'args': encoded([value])
		'mode': json2.Any(mode)
	})!
}
