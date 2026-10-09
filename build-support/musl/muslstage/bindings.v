// SPDX-License-Identifier: GPL-2.0-or-later
module muslstage

import androidhost as ah
import json2
import packagestore

fn callback(name string, args map[string]ah.Value) !ah.Value {
	return packagestore.borrowed_binding(name, args)!
}

fn v(value ah.Value) ah.Value { return ah.Value([ah.Value('value'), value]) }

fn o(value string) ah.Value { return ah.Value([ah.Value('owner'), ah.Value(value)]) }

fn invoke(name string, args []ah.Value, kwargs map[string]ah.Value) !string {
	return callback('function', {
		'call':   ah.Value(true)
		'name':   ah.Value(name)
		'args':   ah.Value(args)
		'kwargs': ah.Value(kwargs)
	})!.text()
}

fn call(name string, args ...ah.Value) !string { return invoke(name, args, {})! }

fn method(id string, name string, args []ah.Value, kwargs map[string]ah.Value) !string {
	return callback('function', {
		'call':   ah.Value(true)
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

fn literal(value ah.Value) !string {
	return callback('literal', {
		'value': v(value)
	})!.text()
}

fn datum(name string, args []ah.Value) !ah.Value {
	return callback('function', {
		'call': ah.Value(true)
		'name': ah.Value(name)
		'args': ah.Value(args)
		'data': ah.Value(true)
	})!
}

fn truth(id string) !bool { return datum('builtins.bool', [o(id)])! as bool }

fn compare(name string, left string, right string) !bool {
	return truth(call('operator.' + name, o(left), o(right))!)!
}

fn detail(err IError) ah.Value {
	if err is packagestore.BindingError { return ah.Value(err.value) }
	return ah.Value(json2.Null{})
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

fn none_value() ah.Value { return ah.Value(json2.Null{}) }

fn add(left string, right string) !string { return call('operator.add', o(left), o(right))! }

fn release(ids ...string) ! {
	callback('release', {
		'ids': ah.Value(ids.map(ah.Value(it)))
	})!
}

fn release_error(ids []string, cause IError) ! {
	callback('active_error', {
		'error': detail(cause)
	})!
	callback('release', {
		'ids': ah.Value(ids.map(ah.Value(it)))
	})!
	callback('active_error', {
		'error': none_value()
	})!
}
