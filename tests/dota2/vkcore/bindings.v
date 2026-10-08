// SPDX-License-Identifier: GPL-2.0-or-later
module vkcore

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
fn attr(id string, name string) !string { return method(id, name, [], {})! }
fn data(id string) !ah.Value { return gc.invoke('operator.pos', [o(id)], {}, 'value')! }
fn truth(id string) !bool { return gc.flag(gc.call('builtins.bool', o(id))!) }
fn text(id string) !string { return gc.call('builtins.str', o(id))!.text() }
fn format(id string) !string { return gc.call('builtins.format', o(id), s(''))!.text() }
fn eq(a string, z ah.Value) !bool { return gc.flag(gc.call('operator.eq', o(a), z)!) }
fn compare(name string, a string, z ah.Value) !bool { return gc.flag(gc.call('operator.' + name, o(a), z)!) }
fn get(id string, key ah.Value) !string { return call('operator.getitem', o(id), key)! }
fn set(id string, key string, value ah.Value) ! { call('operator.setitem', o(id), s(key), value)! }
fn join(id string, name string) !string { return call('operator.truediv', o(id), s(name))! }
fn path(id string) !string { return call('Path', o(id))! }
fn imported_callback(name string, args map[string]ah.Value) !ah.Value { return gc.callback(name, args)! }
fn literal(value ah.Value) !string { return call('json.loads', s(ah.encode(value)))! }
fn null_id() !string { return literal(ah.Value(json2.Null{}))! }
fn list() !string { return call('builtins.list')! }
fn append(id string, value ah.Value) ! { method(id, 'append', [value], {})! }
fn dict() !string { return call('builtins.dict')! }
fn pair(a string, z string) !string {
	items := list()!
	append(items, o(a))!
	append(items, o(z))!
	return call('builtins.tuple', o(items))!
}
fn iter(id string) !string { return call('builtins.iter', o(id))! }
struct Next { done bool
	id string }
fn next(id string) !Next {
	row := gc.callback('next', {'id': ah.Value(id)})!.object()
	if gc.flag(ah.field(row, 'done')) { return Next{done: true} }
	return Next{id: ah.field(row, 'owner').text()}
}
fn enter(id string) !string { return method(id, '__enter__', [], {})! }
fn retire(id string, cause ?IError) !bool {
	mut detail := ah.Value(json2.Null{})
	if error := cause { detail = gc.error_detail(error) }
	return gc.flag(gc.callback('context_exit', {'id': ah.Value(id), 'error': detail})!)
}
fn fail(name string, message string) ! {
	return gc.BindingError{value: {'kind': ah.Value(name), 'message': ah.Value(message),
		'value_error': ah.Value(name == 'ValueError'), 'os_error': ah.Value(false),
		'called_process': ah.Value(false)}}
}
fn export(id string) ah.Value { return ah.Value({'owner_result': ah.Value(id)}) }
fn print_json(id string, indent bool) ! {
	keywords := if indent { {'indent': n(2)} } else { map[string]ah.Value{} }
	encoded := invoke('json.dumps', [o(id)], keywords)!
	call('builtins.print', o(encoded))!
}
fn write_json(location string, id string) ! {
	encoded := invoke('json.dumps', [o(id)], {'indent': n(2)})!
	content := call('operator.add', o(encoded), s('\n'))!
	method(location, 'write_text', [o(content)], {})!
}
fn mkdir(id string) ! { method(id, 'mkdir', [], {'parents': v(ah.Value(true)), 'exist_ok': v(ah.Value(true))})! }
