// SPDX-License-Identifier: GPL-2.0-or-later
module vulkanbuild

import encoding.hex
import hosttest
import json2
import os
import qemubuild

pub struct BindingFailure {
pub:
	value map[string]json2.Any
}

pub fn (e BindingFailure) msg() string { return 'Vulkan primitive failed' }

pub fn (e BindingFailure) code() int { return 0 }

pub struct StageError {
pub:
	kind    string
	message string
}

pub fn (e StageError) msg() string { return e.message }

pub fn (e StageError) code() int { return 0 }

fn fail(message string) IError { return StageError{'SystemExit', message} }

fn argument_error(message string) IError { return StageError{'ArgumentError', message} }

fn field(row map[string]json2.Any, name string) json2.Any { return row[name] or { json2.Null{} } }

fn text(row map[string]json2.Any, name string) string { return field(row, name).str() }

fn paths(value string) json2.Any {
	return json2.Any({
		'path_hex': json2.Any(value.bytes().hex())
	})
}

fn path(value json2.Any) !string { return hex.decode(value.as_map()['path_hex']!.str())!.bytestr() }

fn words(values []string) json2.Any { return json2.Any(values.map(json2.Any(it))) }

fn request(row map[string]json2.Any) !json2.Any {
	println(json2.encode({
		'callback': json2.Any(row)
	}, escape_unicode: true))
	reply := hosttest.decode_json(os.get_raw_line())!.as_map()
	if 'error' in reply { return BindingFailure{reply['error']!.as_map()} }
	return reply['value']!
}

fn public(name string, arguments []json2.Any) !json2.Any {
	return request({
		'kind':      json2.Any('public')
		'name':      json2.Any(name)
		'arguments': json2.Any(arguments)
	})!
}

fn global(name string) !json2.Any {
	return request({
		'kind': json2.Any('global')
		'name': json2.Any(name)
	})!
}

fn constant(name string) !string { return global(name)!.str() }

fn attribute(target json2.Any, name string) !json2.Any {
	return request({
		'kind':   json2.Any('attribute')
		'target': target
		'name':   json2.Any(name)
	})!
}

fn method(target json2.Any, name string, arguments []json2.Any) !json2.Any {
	return request({
		'kind':      json2.Any('method')
		'target':    target
		'name':      json2.Any(name)
		'arguments': json2.Any(arguments)
	})!
}

fn command(kind string, argv []string, keywords map[string]json2.Any) !json2.Any {
	return request({
		'kind':      json2.Any(kind)
		'arguments': json2.Any([words(argv)])
		'keywords':  json2.Any(keywords)
	})!
}

fn decode_json(value string) !json2.Any {
	return request({
		'kind':     json2.Any('json_loads')
		'data_hex': json2.Any(value.bytes().hex())
	})!
}

fn dumps(value json2.Any, sorted bool, pretty bool) !string {
	mut keywords := map[string]json2.Any{}
	if sorted { keywords['sort_keys'] = json2.Any(true) }
	if pretty { keywords['indent'] = json2.Any(2) }
	return request({
		'kind':      json2.Any('json_dumps')
		'arguments': json2.Any([value])
		'keywords':  json2.Any(keywords)
	})!.str()
}

fn digest(value string) !string { return public('file_sha256', [paths(value)])!.str() }

fn package(value json2.Any) map[string]json2.Any {
	return value.as_map()['fields'] or { json2.Any(map[string]json2.Any{}) }.as_map()
}

fn write_json(value string, data json2.Any, sorted bool) ! {
	write_text(value, dumps(data, sorted, true)! + '\n')!
}

fn write_text(value string, data string) ! { qemubuild.write(value, data)! }

// Python str.strip includes its Unicode whitespace and the four separator
// controls; V's ASCII trim_space omits them.
fn strip_space(value string) string {
	runes := value.runes()
	mut first := 0
	mut last := runes.len
	for first < last && python_space(runes[first]) { first++ }
	for last > first && python_space(runes[last - 1]) { last-- }
	return runes[first..last].string()
}

fn python_space(ch rune) bool {
	return ch in [`\t`, `\n`, `\v`, `\f`, `\r`, ` `, rune(0x85), rune(0xa0), rune(0x1680),
		rune(0x2028), rune(0x2029), rune(0x202f), rune(0x205f), rune(0x3000)] || (ch >= 0x1c && ch <= 0x1f) || (ch >= 0x2000 && ch <= 0x200a)
}

pub fn failure_record(err IError) map[string]json2.Any {
	if err is BindingFailure { return err.value }
	if err is StageError {
		return {
			'kind':    json2.Any(err.kind)
			'message': json2.Any(err.message)
		}
	}
	if err is qemubuild.FileError {
		return {
			'kind':     json2.Any('OSError')
			'errno':    json2.Any(err.number)
			'filename': json2.Any(err.filename.bytes().hex())
		}
	}
	if err is qemubuild.RenameError {
		return {
			'kind':      json2.Any('OSError')
			'errno':     json2.Any(err.number)
			'filename':  json2.Any(err.source.bytes().hex())
			'filename2': json2.Any(err.destination.bytes().hex())
		}
	}
	if err is qemubuild.CopyError {
		return {
			'kind':    json2.Any('CopyError')
			'entries': json2.Any(err.entries.map(json2.Any([
				json2.Any(it.source.bytes().hex()),
				json2.Any(it.destination.bytes().hex()),
				json2.Any(it.message),
			])))
		}
	}
	if err is hosttest.ModuleFileError {
		return {
			'kind':     json2.Any('OSError')
			'errno':    json2.Any(err.number)
			'filename': json2.Any(err.filename.bytes().hex())
		}
	}
	if err is hosttest.ModuleDecodeError {
		return {
			'kind':   json2.Any('UnicodeDecodeError')
			'data':   json2.Any(err.data.hex())
			'start':  json2.Any(err.start)
			'end':    json2.Any(err.end)
			'reason': json2.Any(err.reason)
		}
	}
	return {
		'kind':    json2.Any('ValueError')
		'message': json2.Any(err.msg())
	}
}
