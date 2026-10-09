// SPDX-License-Identifier: GPL-2.0-or-later
module wakeguest

import androidhost as ah
import gapcore as gc
import json2

pub fn ignore_interrupt() { gc.ignore_interrupt() }

pub fn finished() ! { gc.finished()! }

pub type BindingError = gc.BindingError

fn o(id string) ah.Value { return gc.owner(id) }

fn v(value ah.Value) ah.Value { return gc.v(value) }

fn s(value string) ah.Value { return v(ah.Value(value)) }

fn n(value int) ah.Value { return v(ah.Value(value)) }

fn b(value string) ah.Value { return gc.b(value) }

fn global(name string) !string {
	return gc.callback('resolve', {
		'name': ah.Value(if name in ['bytearray', 'bytes'] { 'builtins.' + name } else { name })
	})!.text()
}

fn call(name string, args ...ah.Value) !string {
	return gc.callback('function', {
		'name':   ah.Value(if name in ['bytearray', 'bytes'] { 'builtins.' + name } else { name })
		'args':   ah.Value(args)
		'result': ah.Value('owner')
		'call':   ah.Value(true)
	})!.text()
}

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

fn truth(id string) !bool {
	return gc.callback('truth', {
		'id': ah.Value(id)
	})! as bool
}

fn attr(id string, name string) !string {
	return gc.callback('attribute', {
		'id':   ah.Value(id)
		'name': ah.Value(if name in ['bytearray', 'bytes'] { 'builtins.' + name } else { name })
	})!.text()
}

fn compare(name string, left string, right string) !bool {
	return truth(call('operator.' + name, o(left), o(right))!)!
}

fn item(id string, index int) !string { return call('operator.getitem', o(id), n(index))! }

fn join(parent string, child string) !string {
	return call('operator.truediv', o(parent), s(child))!
}

fn exception(err IError, name string) !bool {
	return gc.callback('exception_matches', {
		'error': gc.error_detail(err)
		'class': ah.Value(global(name)!)
	})! as bool
}

fn exception_any(err IError, names []string) !bool {
	mut classes := []ah.Value{}
	for name in names { classes << ah.Value(global(name)!) }
	return gc.callback('exception_matches', {
		'error':   gc.error_detail(err)
		'classes': ah.Value(classes)
	})! as bool
}

fn export(id string) ah.Value {
	return ah.Value({
		'owner_result': ah.Value(id)
	})
}

fn retire(id string, cause ?IError) !bool {
	return gc.flag(gc.callback('context_exit', {
		'id':    ah.Value(id)
		'error': if e := cause { gc.error_detail(e) } else { ah.Value(json2.Null{}) }
	})!)
}

fn active(cause ?IError) ! {
	gc.callback('active_error', {
		'error': if e := cause { gc.error_detail(e) } else { ah.Value(json2.Null{}) }
	})!
}

fn discard(id string) ! {
	gc.callback('release', {
		'ids': ah.Value([ah.Value(id)])
	})!
}

fn enter(id string) !string { return method(id, '__enter__', [], {})! }

fn list(values []string) !string {
	id := gc.callback('list_new', {})!.text()
	for value in values { method(id, 'append', [o(value)], {})! }
	return id
}
