// SPDX-License-Identifier: GPL-2.0-or-later
module robloxguest

import androidhost as ah
import gapcore as gc
import json2

fn v(value ah.Value) ah.Value { return gc.v(value) }

fn o(id string) ah.Value { return gc.owner(id) }

fn s(value string) ah.Value { return v(ah.Value(value)) }

fn n(value int) ah.Value { return v(ah.Value(value)) }

fn b(hex string) ah.Value { return gc.b(hex) }

fn invoke(name string, args []ah.Value, kwargs map[string]ah.Value) !string {
	actual := if name in ['print', 'str', 'bytes', 'bytearray'] { 'builtins.' + name } else { name }
	return gc.callback('function', {
		'name':   ah.Value(actual)
		'args':   ah.Value(args)
		'kwargs': ah.Value(kwargs)
		'result': ah.Value('owner')
		'call':   ah.Value(true)
	})!.text()
}

fn call(name string, args ...ah.Value) !string { return invoke(name, args, {})! }

fn method(id string, name string, args []ah.Value, kwargs map[string]ah.Value) !string {
	return gc.callback('function', {
		'owner':  ah.Value(id)
		'method': ah.Value(name)
		'args':   ah.Value(args)
		'kwargs': ah.Value(kwargs)
		'result': ah.Value('owner')
		'call':   ah.Value(true)
	})!.text()
}

fn attr(id string, name string) !string {
	return gc.callback('attribute', {
		'id':   ah.Value(id)
		'name': ah.Value(name)
	})!.text()
}

fn truth(id string) !bool {
	return gc.flag(gc.callback('truth', {
		'id': ah.Value(id)
	})!)
}

fn text(id string) !string { return gc.call('builtins.str', o(id))!.text() }

fn format(id string) !string {
	return gc.callback('format', {
		'id':   ah.Value(id)
		'spec': ah.Value('')
	})!.text()
}

fn eq(a string, z ah.Value) !bool { return truth(call('operator.eq', o(a), z)!) }

fn compare(name string, a string, z ah.Value) !bool {
	return truth(call('operator.' + name, o(a), z)!)
}

fn get(id string, key ah.Value) !string { return call('operator.getitem', o(id), key)! }

fn set(id string, key string, value ah.Value) ! { call('operator.setitem', o(id), s(key), value)! }

fn join(id string, name string) !string { return call('operator.truediv', o(id), s(name))! }

fn literal(value ah.Value) !string {
	return gc.callback('literal', {
		'value': value
	})!.text()
}

fn list() !string { return literal(ah.Value([]ah.Value{}))! }

fn append(id string, value ah.Value) ! { method(id, 'append', [value], {})! }

fn dict() !string { return literal(ah.Value(map[string]ah.Value{}))! }

fn enter(id string) !string { return method(id, '__enter__', [], {})! }

fn retire(id string, cause ?IError) !bool {
	mut detail := ah.Value(json2.Null{})
	if error := cause { detail = gc.error_detail(error) }
	return gc.flag(gc.callback('context_exit', {
		'id':    ah.Value(id)
		'error': detail
	})!)
}

fn export(id string) ah.Value {
	return ah.Value({
		'owner_result': ah.Value(id)
	})
}
