// SPDX-License-Identifier: GPL-2.0-or-later
module packagestore

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

fn callback(name string, args map[string]ah.Value) !ah.Value {
	println(ah.encode(boothost.pack(ah.Value({
		'callback':  ah.Value(name)
		'arguments': ah.Value(args)
	}))))
	row := boothost.unpack(json2.decode[ah.Value](os.get_raw_line())!)!.object()
	if 'error' in row { return BindingError{ah.field(row, 'error').object()} }
	return ah.field(row, 'value')
}

fn v(value ah.Value) ah.Value { return ah.Value([ah.Value('value'), value]) }

fn o(value string) ah.Value { return ah.Value([ah.Value('owner'), ah.Value(value)]) }

fn b(value string) ah.Value { return ah.Value([ah.Value('bytes'), ah.Value(value)]) }

fn invoke(name string, args []ah.Value, kwargs map[string]ah.Value) !string {
	return callback('function', {
		'name':   ah.Value(name)
		'args':   ah.Value(args)
		'kwargs': ah.Value(kwargs)
	})!.text()
}

fn call(name string, args ...ah.Value) !string { return invoke(name, args, {})! }

fn method(id string, name string, args []ah.Value, kwargs map[string]ah.Value) !string {
	return callback('function', {
		'owner':  ah.Value(id)
		'name':   ah.Value(name)
		'args':   ah.Value(args)
		'kwargs': ah.Value(kwargs)
	})!.text()
}

fn attribute(id string, name string) !string {
	return callback('attribute', {
		'owner': ah.Value(id)
		'name':  ah.Value(name)
	})!.text()
}

fn set_attr(id string, name string, value ah.Value) ! {
	callback('set_attribute', {
		'owner': ah.Value(id)
		'name':  ah.Value(name)
		'value': value
	})!
}

fn literal(value ah.Value) !string {
	return callback('literal', {
		'value': v(value)
	})!.text()
}

fn bytes(hex string) !string {
	return callback('literal', {
		'value': b(hex)
	})!.text()
}

fn collection(kind string, items []string) !string {
	return callback('collection', {
		'kind':   ah.Value(kind)
		'values': ah.Value(items.map(ah.Value(it)))
	})!.text()
}

fn datum(name string, args []ah.Value) !ah.Value {
	return callback('function', {
		'name': ah.Value(name)
		'args': ah.Value(args)
		'data': ah.Value(true)
	})!
}

fn text(id string) !string { return datum('builtins.format', [o(id), v(ah.Value(''))])!.text() }

fn truth(id string) !bool { return datum('builtins.bool', [o(id)])! as bool }

fn compare(name string, left string, right string) !bool {
	return datum('operator.' + name, [o(left), o(right)])! as bool
}

fn join(parent string, child string) !string {
	return call('operator.truediv', o(parent), v(ah.Value(child)))!
}

fn null() !string { return literal(ah.Value(json2.Null{}))! }

fn iterator(value string) !string { return call('builtins.iter', o(value))! }

struct Next {
	done  bool
	value string
}

fn next(id string) !Next {
	row := callback('next', {
		'owner': ah.Value(id)
	})!.object()
	if ah.field(row, 'done') as bool { return Next{ done: true } }
	return Next{ value: ah.field(row, 'value').text() }
}

fn kind(err IError, name string) bool {
	if err is BindingError { return ah.field(err.value, name) as bool }
	return false
}

fn detail(err IError) ah.Value {
	if err is BindingError { return ah.Value(err.value) }
	return ah.Value(json2.Null{})
}

fn activate(cause ?IError) ! {
	mut row := { 'error': ah.Value(json2.Null{}) }
	if error := cause { row['error'] = detail(error) }
	callback('active_error', row)!
}

fn failed(kind string, message string, cause ?IError) ! {
	mut row := {
		'kind':    ah.Value(kind)
		'message': ah.Value(message)
	}
	if error := cause { row['cause'] = detail(error) }
	callback('raise', row)!
}

fn enter(id string) !string {
	return callback('enter', {
		'owner': ah.Value(id)
	})!.text()
}

fn retire(id string, cause ?IError) !bool {
	mut row := {
		'owner': ah.Value(id)
		'error': ah.Value(json2.Null{})
	}
	if error := cause { row['error'] = detail(error) }
	return callback('exit', row)! as bool
}

fn own(id string, name string) ! {
	callback('own', {
		'owner':  ah.Value(id)
		'method': ah.Value(name)
	})!
}

fn own_function(id string, name string) ! {
	callback('own', {
		'owner':    ah.Value(id)
		'function': ah.Value(name)
	})!
}

fn close(id string, cause ?IError) ! {
	mut row := {
		'owner': ah.Value(id)
		'error': ah.Value(json2.Null{})
	}
	if error := cause { row['error'] = detail(error) }
	callback('close', row)!
}

fn transfer(id string) ! {
	callback('transfer', {
		'owner': ah.Value(id)
	})!
}

fn log(message string) ! {
	invoke('print', [v(ah.Value(message))], {
		'flush': v(ah.Value(true))
	})!
}
