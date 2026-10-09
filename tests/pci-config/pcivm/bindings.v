// SPDX-License-Identifier: GPL-2.0-or-later
module pcivm

import androidhost as ah
import json2
import packagestore

fn callback(name string, args map[string]ah.Value) !ah.Value {
	return packagestore.borrowed_binding(name, args)!
}

fn o(id string) ah.Value { return ah.Value([ah.Value('owner'), ah.Value(id)]) }

fn v(value ah.Value) ah.Value { return ah.Value([ah.Value('value'), value]) }

fn resolve(name string) !string {
	return callback('resolve', {
		'name': ah.Value(name)
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

fn target_call(target string, args []ah.Value, kwargs map[string]ah.Value) !string {
	return callback('function', {
		'target': ah.Value(target)
		'call':   ah.Value(true)
		'args':   ah.Value(args)
		'kwargs': ah.Value(kwargs)
	})!.text()
}

fn call(name string, args ...ah.Value) !string {
	target := resolve(name)!
	result := target_call(target, args, {}) or {
		release(target)!
		return err
	}
	release(target)!
	return result
}

fn method(id string, name string, args []ah.Value, kwargs map[string]ah.Value) !string {
	target := attribute(id, name)!
	result := target_call(target, args, kwargs) or {
		release(target)!
		return err
	}
	release(target)!
	return result
}

fn release(ids ...string) ! {
	callback('release', {
		'ids': ah.Value(ids.map(ah.Value(it)))
	})!
}

fn discard(id string) ! { release(id)! }

fn datum(name string, args []ah.Value) !ah.Value {
	return callback('function', {
		'name': ah.Value(name)
		'call': ah.Value(true)
		'args': ah.Value(args)
		'data': ah.Value(true)
	})!
}

fn truth(id string) !bool { return datum('builtins.bool', [o(id)])! as bool }

fn null(id string) !bool {
	return datum('operator.is_', [o(id), v(ah.Value(json2.Null{}))])! as bool
}

fn flag(args string, name string) !bool {
	value := attribute(args, name)!
	result := truth(value) or {
		discard(value)!
		return err
	}
	discard(value)!
	return result
}

fn add(left string, right string) !string { return call('operator.add', o(left), o(right))! }

fn joined(prefix string, value string) !string {
	start := literal(ah.Value(prefix))!
	result := add(start, value) or {
		discard(start)!
		return err
	}
	discard(start)!
	return result
}

fn formatted(value string) !string { return call('builtins.format', o(value), v(ah.Value('')))! }

fn set_item(owner string, name string, value ah.Value) ! {
	discard(call('operator.setitem', o(owner), v(ah.Value(name)), value)!)!
}

fn detail(cause IError) ah.Value {
	if cause is packagestore.BindingError { return ah.Value(cause.value) }
	return ah.Value(json2.Null{})
}

fn active(cause ?IError) ! {
	callback('active_error', {
		'error': if error := cause { detail(error) } else { ah.Value(json2.Null{}) }
	})!
}

fn matches(cause IError, name string) !bool {
	class := resolve(name)!
	value := callback('exception_matches', {
		'error': detail(cause)
		'class': ah.Value(class)
	}) or {
		discard(class)!
		return err
	}
	discard(class)!
	return value as bool
}

fn raise_message(target string, message string) ! {
	error_obj := target_call(target, [o(message)], {}) or {
		release(message, target)!
		return err
	}
	release(message, target)!
	raiser := resolve('_pci_raise') or {
		discard(error_obj)!
		return err
	}
	target_call(raiser, [o(error_obj)], {}) or {
		release(error_obj, raiser)!
		return err
	}
	release(error_obj, raiser)!
}

fn runtime_error(prefix string, value string) ! {
	target := resolve('RuntimeError')!
	text := formatted(value) or {
		discard(target)!
		return err
	}
	message := joined(prefix, text) or {
		release(text, target)!
		return err
	}
	discard(text)!
	raise_message(target, message)!
}

fn error_text(message string) ! {
	target := resolve('RuntimeError')!
	raise_message(target, literal(ah.Value(message))!)!
}

fn checkpoint() !ah.Value { return callback('checkpoint', {})! }

fn sweep(point ah.Value, keep []string) ! {
	callback('release_since', {
		'checkpoint': point
		'keep':       ah.Value(keep.map(ah.Value(it)))
	})!
}
