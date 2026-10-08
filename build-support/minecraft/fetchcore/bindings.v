// SPDX-License-Identifier: GPL-2.0-or-later
module fetchcore

import androidhost as ah
import boothost
import json2
import os

pub struct BindingError {
pub:
	value map[string]ah.Value
}

pub fn (e BindingError) msg() string { return ah.field(e.value, 'message').text() }

pub fn (e BindingError) code() int { return 0 }

pub struct PolicyError {
pub:
	kind    string
	message string
}

pub fn (e PolicyError) msg() string { return e.message }

pub fn (e PolicyError) code() int { return 0 }

fn failed(kind string, message string) IError { return PolicyError{kind, message} }

fn callback(operation string, arguments map[string]ah.Value) !ah.Value {
	println(ah.encode(boothost.pack(ah.Value({
		'callback':  ah.Value(operation)
		'arguments': ah.Value(arguments)
	}))))
	row := boothost.unpack(json2.decode[ah.Value](os.get_raw_line())!)!.object()
	if 'error' in row { return BindingError{ah.field(row, 'error').object()} }
	return ah.field(row, 'value')
}

fn method(name string, arguments []ah.Value) !ah.Value {
	return callback('method', {
		'name':      ah.Value(name)
		'arguments': ah.Value(arguments)
	})!
}

fn get(value ah.Value, key string, default_value ah.Value) !ah.Value {
	return method('get', [value, ah.Value(key), default_value])!
}

fn item(value ah.Value, key ah.Value) !ah.Value {
	return callback('index', {
		'arguments': ah.Value([value, key])
	})!
}

fn builtin(name string, values ...ah.Value) !ah.Value {
	return callback('builtin', {
		'name':      ah.Value(name)
		'arguments': ah.Value(values)
	})!
}

fn truth(value ah.Value) !bool { return boolean(builtin('bool', value)!) }

fn equal(left ah.Value, right ah.Value) !bool { return compare('eq', left, right)! }

fn compare(name string, left ah.Value, right ah.Value) !bool {
	return boolean(callback('compare', {
		'name':      ah.Value(name)
		'arguments': ah.Value([left, right])
	})!)
}

fn stringify(value ah.Value) !string { return builtin('str', value)!.text() }

fn iterable(value ah.Value) ![]ah.Value { return builtin('list', value)!.items() }

fn path(name string, value string, arguments []ah.Value, options map[string]ah.Value) !ah.Value {
	return callback('path', {
		'path':      ah.Value(value)
		'method':    ah.Value(name)
		'arguments': ah.Value(arguments)
		'options':   ah.Value(options)
	})!
}

fn join(parent string, child ah.Value) !string {
	return callback('join', {
		'parent': ah.Value(parent)
		'child':  child
	})!.text()
}

fn test(name string, value string) !bool {
	return boolean(path(name, value, []ah.Value{}, map[string]ah.Value{})!)
}

fn mkdir(value string) ! {
	path('mkdir', value, []ah.Value{}, {
		'parents':  ah.Value(true)
		'exist_ok': ah.Value(true)
	})!
}

fn public(name string, args []ah.Value, binary bool) !ah.Value {
	return callback('public', {
		'name':   ah.Value(name)
		'args':   ah.Value(args)
		'binary': ah.Value(binary)
	})!
}

fn argument(kind string, value ah.Value) ah.Value { return ah.Value([ah.Value(kind), value]) }

fn log(message string) ! { public('log', [argument('value', ah.Value(message))], false)! }

fn json_load(data ah.Value, binary bool) !ah.Value {
	return callback('json', {
		'data':   data
		'binary': ah.Value(binary)
	})!
}

fn null() ah.Value { return ah.Value(json2.Null{}) }

fn boolean(value ah.Value) bool {
	if value is bool { return value }
	return false
}

fn constant(name string) !ah.Value {
	return callback('constant', {
		'name': ah.Value(name)
	})!
}

fn error_value(cause IError) ah.Value {
	if cause is BindingError { return ah.Value(cause.value) }
	return ah.Value({
		'kind':    ah.Value('RuntimeError')
		'message': ah.Value(cause.msg())
	})
}

fn retire(owner ah.Value, cause ?IError) !bool {
	return truth(callback('close_handle', {
		'id':    owner
		'error': if failure := cause { error_value(failure) } else { null() }
	})!)!
}
