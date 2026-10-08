// SPDX-License-Identifier: GPL-2.0-only
module stagehost

import encoding.hex
import json2
import os

pub struct BindingError {
pub:
	value map[string]json2.Any
}

pub fn (e BindingError) msg() string {
	return decode(e.value['message'] or { json2.Any('') }.str()) or { 'stdlib staging primitive failed' }
}

pub fn (e BindingError) code() int { return 0 }

pub struct StageError {
pub:
	message string
}

pub fn (e StageError) msg() string { return e.message }

pub fn (e StageError) code() int { return 0 }

fn failure(value string) IError { return StageError{value} }

fn decode(value string) !string { return hex.decode(value)!.bytestr() }

fn callback(operation string, arguments map[string]json2.Any) !json2.Any {
	println(json2.encode({
		'callback':  json2.Any(operation)
		'arguments': json2.Any(arguments)
	},
		escape_unicode: true
	))
	row := json2.decode[json2.Any](os.get_raw_line())!.as_map()
	if 'error' in row { return BindingError{row['error']!.as_map()} }
	return row['value']!
}

fn encoded(values []string) json2.Any { return json2.Any(values.map(json2.Any(it.bytes().hex()))) }

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

fn join(values []string) !string { return path('join', values)! }

fn test(function string, value string) !bool {
	return callback('test', {
		'function': json2.Any(function)
		'args':     encoded([value])
	})!.bool()
}

fn names(value string) ![]string {
	return primitive('list', [value])!.as_array().map(decode(it.str())!)
}

fn read(value string, encoding string) !string {
	mut args := {
		'args':   encoded([value])
		'binary': json2.Any(false)
	}
	if encoding != '' { args['encoding'] = encoding }
	return decode(callback('read', args)!.str())!
}

fn read_bytes(value string) ![]u8 {
	return hex.decode(callback('read', {
		'args':   encoded([value])
		'binary': json2.Any(true)
	})!.str())!
}

fn write(value string, text string, encoding string) ! {
	mut args := {
		'args': encoded([value, text])
	}
	if encoding != '' { args['encoding'] = encoding }
	callback('write', args)!
}

fn regex(pattern string, text string, flags int) ![]json2.Any {
	return callback('regex', {
		'args':  encoded([pattern, text])
		'flags': json2.Any(flags)
		'full':  json2.Any(false)
	})!.as_array()
}

fn full(pattern string, text string) !bool {
	return callback('regex', {
		'args':  encoded([pattern, text])
		'flags': json2.Any(0)
		'full':  json2.Any(true)
	})!.bool()
}

fn mkdir(value string, exist_ok bool) ! {
	callback('mkdir', {
		'args':     encoded([value])
		'exist_ok': json2.Any(exist_ok)
	})!
}

fn remove_existing(value string) ! { if test('lexists', value)! { primitive('remove', [value])! } }
