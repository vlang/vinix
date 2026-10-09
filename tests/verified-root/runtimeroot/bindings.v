// SPDX-License-Identifier: MIT
module runtimeroot

import androidhost as ah
import json2
import packagestore
import cpythonhost

fn callback(name string, args map[string]ah.Value) !ah.Value {
	$if cpython_host ? {
		return cpythonhost.callback(name, args)!
	} $else {
		return packagestore.borrowed_binding(name, args)!
	}
}

fn v(value ah.Value) ah.Value { return ah.Value([ah.Value('value'), value]) }

fn o(value string) ah.Value { return ah.Value([ah.Value('owner'), ah.Value(value)]) }

fn invoke(name string, args []ah.Value, kwargs map[string]ah.Value) !string {
	return callback('function', {
		'name':   ah.Value(name)
		'call':   ah.Value(true)
		'args':   ah.Value(args)
		'kwargs': ah.Value(kwargs)
	})!.text()
}

fn call(name string, args ...ah.Value) !string { return invoke(name, args, {})! }

fn method(id string, name string, args []ah.Value, kwargs map[string]ah.Value) !string {
	return callback('function', {
		'owner':  ah.Value(id)
		'name':   ah.Value(name)
		'call':   ah.Value(true)
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

fn literal(value ah.Value) !string {
	return callback('literal', {
		'value': v(value)
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
	return truth(call('operator.' + name, o(left), o(right))!)!
}

fn join(parent string, child string) !string {
	return call('operator.truediv', o(parent), v(ah.Value(child)))!
}


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

fn detail(err IError) ah.Value {
	if err is packagestore.BindingError { return ah.Value(err.value) }
	$if cpython_host ? {
		if err is cpythonhost.Failure { return ah.Value(err.value) }
	}
	return ah.Value(json2.Null{})
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

fn release(ids ...string) ! {
	callback('release', {
		'ids': ah.Value(ids.map(ah.Value(it)))
	})!
}
