// SPDX-License-Identifier: GPL-2.0-or-later
module guestcore

import androidhost as ah
import gapcore as gc
import json2

fn v(value ah.Value) ah.Value { return gc.v(value) }

fn o(id string) ah.Value { return gc.owner(id) }

fn s(value string) ah.Value { return v(ah.Value(value)) }

fn n(value int) ah.Value { return v(ah.Value(value)) }

fn b(hex string) ah.Value { return gc.b(hex) }

fn invoke(name string, args []ah.Value, kwargs map[string]ah.Value) !string {
	return gc.invoke(name, args, kwargs, 'owner')!.text()
}

fn call(name string, args ...ah.Value) !string { return invoke(name, args, {})! }

fn method(id string, name string, args []ah.Value, kwargs map[string]ah.Value) !string {
	return gc.method(id, name, args, kwargs, 'owner')!.text()
}

fn attr(id string, name string) !string { return call('_vm.attribute_value', o(id), s(name))! }

fn truth(id string) !bool { return gc.flag(gc.call('_vm.truth_value', o(id))!) }

fn text(id string) !string { return gc.call('builtins.str', o(id))!.text() }

fn format(id string) !string { return gc.call('_vm.format_value', o(id))!.text() }

fn eq(a string, z ah.Value) !bool { return truth(call('operator.eq', o(a), z)!)! }

fn compare(name string, a string, z ah.Value) !bool {
	return truth(call('operator.' + name, o(a), z)!)!
}

fn get(id string, key ah.Value) !string { return call('operator.getitem', o(id), key)! }

fn set(id string, key string, value ah.Value) ! { call('operator.setitem', o(id), s(key), value)! }

fn join(id string, name string) !string { return call('operator.truediv', o(id), s(name))! }

fn path(id string) !string { return call('Path', o(id))! }

fn literal(value ah.Value) !string {
	return gc.callback('literal', {
		'value': value
	})!.text()
}

fn null_id() !string { return literal(ah.Value(json2.Null{}))! }

fn list() !string { return literal(ah.Value([]ah.Value{}))! }

fn append(id string, value ah.Value) ! { method(id, 'append', [value], {})! }

fn dict() !string { return literal(ah.Value(map[string]ah.Value{}))! }

struct Next {
	done bool
	id   string
}

fn next(id string) !Next {
	row := gc.callback('next', {
		'id': ah.Value(id)
	})!.object()
	if gc.flag(ah.field(row, 'done')) { return Next{ done: true } }
	return Next{ id: ah.field(row, 'owner').text() }
}

fn release(ids ...string) ! {
	gc.callback('release', {
		'ids': ah.Value(ids.map(ah.Value(it)))
	})!
}

fn checkpoint() !ah.Value {
	return gc.callback('checkpoint', {})!
}

fn release_since(mark ah.Value, keep ...string) ! {
	gc.callback('release_since', {
		'checkpoint': mark
		'keep':       ah.Value(keep.map(ah.Value(it)))
	})!
}

fn enter(id string) !string { return method(id, '__enter__', [], {})! }

fn retire(id string, cause ?IError) !bool {
	mut detail := ah.Value(json2.Null{})
	if error := cause { detail = gc.error_detail(error) }
	return gc.flag(gc.callback('context_exit', {
		'id':    ah.Value(id)
		'error': detail
	})!)
}

fn fail(name string, message string) ! {
	call('_vm.raise_error', o(call('builtins.' + name, s(message))!))!
}

fn export(id string) ah.Value {
	return ah.Value({
		'owner_result': ah.Value(id)
	})
}

fn print_json(id string, indent bool) ! {
	keywords := if indent {
		{
			'indent': n(2)
		}
	} else {
		map[string]ah.Value{}
	}
	encoded := invoke('json.dumps', [o(id)], keywords)!
	call('builtins.print', o(encoded))!
}

fn write_json(location string, id string) ! {
	encoded := invoke('json.dumps', [o(id)], {
		'indent': n(2)
	})!
	content := call('operator.add', o(encoded), s('\n'))!
	method(location, 'write_text', [o(content)], {})!
}

fn mkdir(id string) ! {
	method(id, 'mkdir', [], {
		'parents':  v(ah.Value(true))
		'exist_ok': v(ah.Value(true))
	})!
}
