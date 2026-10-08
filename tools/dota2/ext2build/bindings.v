// SPDX-License-Identifier: GPL-2.0-or-later
module ext2build

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

// Independent fixtures share the transport, without production dispatch.
pub fn borrowed_binding(name string, args map[string]ah.Value) !ah.Value {
	return callback(name, args)!
}

fn v(value ah.Value) ah.Value { return ah.Value([ah.Value('value'), value]) }

fn o(id string) ah.Value { return ah.Value([ah.Value('owner'), ah.Value(id)]) }

fn b(data string) ah.Value { return ah.Value([ah.Value('bytes'), ah.Value(data)]) }

fn invoke(name string, args []ah.Value, kwargs map[string]ah.Value) !string {
	return callback('function', {
		'name':   ah.Value(name)
		'args':   ah.Value(args)
		'kwargs': ah.Value(kwargs)
	})!.text()
}

fn call(name string, args ...ah.Value) !string { return invoke(name, args, {})! }

fn api(name string, args ...ah.Value) !string {
	row := callback('dispatch', {
		'name': ah.Value(name)
		'args': ah.Value(args)
	})!.object()
	if ah.field(row, 'native') as bool {
		return dispatch({
			'operation': ah.Value(name)
			'arguments': ah.field(row, 'arguments')
		})!.text()
	}
	return method(ah.field(row, 'target').text(), '__call__', args, {})!
}

fn api_method(id string, name string, args []ah.Value) !string {
	row := callback('dispatch', {
		'owner': ah.Value(id)
		'name':  ah.Value(name)
		'args':  ah.Value(args)
	})!.object()
	if ah.field(row, 'native') as bool {
		return dispatch({
			'operation': ah.Value(name)
			'arguments': ah.field(row, 'arguments')
		})!.text()
	}
	return method(ah.field(row, 'target').text(), '__call__', args, {})!
}

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

fn null() !string { return literal(ah.Value(json2.Null{}))! }

fn collection(kind string, values []string) !string {
	return callback('collection', {
		'kind':   ah.Value(kind)
		'values': ah.Value(values.map(ah.Value(it)))
	})!.text()
}

fn datum(name string, args []ah.Value) !ah.Value {
	return callback('function', {
		'name': ah.Value(name)
		'args': ah.Value(args)
		'data': ah.Value(true)
	})!
}

fn truth(id string) !bool { return datum('builtins.bool', [o(id)])! as bool }

fn text(id string) !string { return datum('builtins.str', [o(id)])!.text() }

fn hex_data(id string) !string {
	return callback('function', {
		'owner': ah.Value(id)
		'name':  ah.Value('hex')
		'data':  ah.Value(true)
	})!.text()
}

fn size(id string) !int {
	return datum('builtins.str', [o(call('builtins.len', o(id))!)])!.text().int()
}

fn number(id string) !i64 { return datum('builtins.str', [o(id)])!.text().i64() }

fn item(id string, key ah.Value) !string { return call('operator.getitem', o(id), key)! }

fn set_item(id string, key ah.Value, value ah.Value) ! {
	call('operator.setitem', o(id), key, value)!
}

fn append(id string, value ah.Value) ! { method(id, 'append', [value], {})! }

fn join(parent string, child string) !string {
	return call('operator.truediv', o(parent), v(ah.Value(child)))!
}

fn compare(name string, left string, right string) !bool {
	return datum('operator.' + name, [o(left), o(right)])! as bool
}

struct Next {
	done  bool
	value string
}

fn iterator(id string) !string { return call('builtins.iter', o(id))! }

fn unpack2(id string) ![]string {
	return callback('unpack2', {
		'owner': ah.Value(id)
	})!.items().map(it.text())
}

fn unpack(id string, count int) ![]string {
	return callback('unpack', {
		'owner': ah.Value(id)
		'count': ah.Value(count)
	})!.items().map(it.text())
}

fn caught(cause IError, kinds []string) !bool {
	if cause is BindingError {
		return callback('exception_is', {
			'error': ah.Value(cause.value)
			'kinds': ah.Value(kinds.map(ah.Value(it)))
		})! as bool
	}
	return false
}

fn next(id string) !Next {
	row := callback('next', {
		'owner': ah.Value(id)
	})!.object()
	if ah.field(row, 'done') as bool { return Next{ done: true } }
	return Next{ value: ah.field(row, 'value').text() }
}

fn failed(kind string, args ...ah.Value) ! {
	callback('raise', {
		'kind': ah.Value(kind)
		'args': ah.Value(args)
	})!
}

fn enter(id string) !string {
	return callback('enter', {
		'owner': ah.Value(id)
	})!.text()
}

fn own(id string, function string) ! {
	callback('own', {
		'owner':    ah.Value(id)
		'function': ah.Value(function)
	})!
}

fn retire(id string, cause ?IError) !bool {
	mut record := ah.Value(json2.Null{})
	if error := cause {
		if error is BindingError { record = ah.Value(error.value) } else { return error }
	}
	return callback('exit', {
		'owner': ah.Value(id)
		'error': record
	})! as bool
}
