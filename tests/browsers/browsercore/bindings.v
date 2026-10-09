// SPDX-License-Identifier: GPL-2.0-or-later
module browsercore

import androidhost as ah
import gapcore as gc
import json2

fn o(id string) ah.Value { return gc.owner(id) }

fn s(value string) ah.Value { return gc.v(ah.Value(value)) }

fn n(value int) ah.Value { return gc.v(ah.Value(value)) }

fn b(hex string) ah.Value { return gc.b(hex) }

fn null() ah.Value { return gc.v(ah.Value(json2.Null{})) }

fn f(value string) ah.Value { return gc.v(ah.Value(ah.Number{value})) }

fn global(name string) !string {
	return gc.callback('resolve', {
		'name': ah.Value(name)
	})!.text()
}

fn attr(id string, name string) !string {
	return gc.callback('attribute', {
		'id':   ah.Value(id)
		'name': ah.Value(name)
	})!.text()
}

fn release(ids []string) ! {
	gc.callback('release', {
		'ids': ah.Value(ids.map(ah.Value(it)))
	})!
}

fn invoke(target string, args []ah.Value, kwargs map[string]ah.Value) !string {
	return gc.callback('invoke', {
		'target': ah.Value(target)
		'args':   ah.Value(args)
		'kwargs': ah.Value(kwargs)
	})!.text()
}

fn evaluated(target string, args []ah.Value, kwargs map[string]ah.Value) !string {
	result := invoke(target, args, kwargs) or {
		cause := err
		release([target])!
		return cause
	}
	release([target])!
	return result
}

fn temporary_call(target string, args []ah.Value, kwargs map[string]ah.Value, temporaries []string) !string {
	result := invoke(target, args, kwargs) or {
		cause := err
		release(temporaries)!
		release([target])!
		return cause
	}
	release(temporaries)!
	release([target])!
	return result
}

fn call(name string, args ...ah.Value) !string { return evaluated(global(name)!, args, {})! }

fn method(id string, name string, args []ah.Value, kwargs map[string]ah.Value) !string {
	return evaluated(attr(id, name)!, args, kwargs)!
}

fn truth(id string) !bool {
	return gc.flag(gc.callback('truth', {
		'id': ah.Value(id)
	})!)
}

fn format(id string) !string {
	return gc.callback('format', {
		'id': ah.Value(id)
	})!.text()
}

fn op(name string, left string, right ah.Value) !string {
	return call('operator.' + name, o(left), right)!
}

fn compare(name string, left string, right ah.Value) !bool { return truth(op(name, left, right)!)! }

fn get(id string, key ah.Value) !string { return op('getitem', id, key)! }

fn join(id string, name string) !string { return op('truediv', id, s(name))! }

fn text(id string) !string { return call('str', o(id))! }

fn path_text(id string, name string) !string {
	target := global('str')!
	path := join(id, name) or {
		release([target])!
		return err
	}
	return temporary_call(target, [o(path)], {}, [path])!
}

fn literal(value ah.Value) !string {
	return gc.callback('literal', {
		'value': value
	})!.text()
}

fn list(values []ah.Value) !string {
	id := gc.callback('list_new', {})!.text()
	for value in values { perform_method(id, 'append', [value], {})! }
	return id
}

fn enter(manager string) !string {
	return gc.callback('function', {
		'owner':  ah.Value(manager)
		'method': ah.Value('__enter__')
		'args':   ah.Value([]ah.Value{})
		'result': ah.Value('owner')
		'call':   ah.Value(true)
	})!.text()
}

fn retire(manager string, cause ?IError) !bool {
	result := gc.callback('context_exit', {
		'id':    ah.Value(manager)
		'error': if e := cause { gc.error_detail(e) } else { ah.Value(json2.Null{}) }
	})!
	return if cause != none { gc.flag(result) } else { false }
}

fn active(cause ?IError) ! {
	gc.callback('active_error', {
		'error': if e := cause { gc.error_detail(e) } else { ah.Value(json2.Null{}) }
	})!
}

fn exception(cause IError, names []string) !bool {
	mut classes := []ah.Value{}
	for name in names { classes << ah.Value(global(name)!) }
	return gc.flag(gc.callback('exception_matches', {
		'error':   gc.error_detail(cause)
		'classes': ah.Value(classes)
	})!)
}

fn export(id string) ah.Value {
	return ah.Value({
		'owner_result': ah.Value(id)
	})
}

fn is_none(id string) !bool {
	return id == '' || gc.flag(gc.callback('is_none', {
		'id': ah.Value(id)
	})!)
}

fn perform(name string, args ...ah.Value) ! { release([call(name, ...args)!])! }

fn perform_method(id string, name string, args []ah.Value, kwargs map[string]ah.Value) ! {
	release([method(id, name, args, kwargs)!])!
}

fn perform_target(target string, args []ah.Value, kwargs map[string]ah.Value) ! {
	release([evaluated(target, args, kwargs)!])!
}

fn discard_error(cause IError) ! {
	gc.callback('discard_error', {
		'error': gc.error_detail(cause)
	})!
}

fn compare_eio(cause IError, comparison string) !bool {
	object := gc.callback('error_object', {
		'error': gc.error_detail(cause)
	})!.text()
	number := attr(object, 'errno') or {
		release([object])!
		return err
	}
	code := global('errno.EIO') or {
		release([object, number])!
		return err
	}
	compared := op(comparison, number, o(code)) or {
		release([object, number, code])!
		return err
	}
	release([number, code])!
	result := truth(compared) or {
		release([object, compared])!
		return err
	}
	release([compared, object])!
	return result
}
