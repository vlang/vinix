// SPDX-License-Identifier: GPL-2.0-or-later
module boottest

import androidhost as ah
import json2
import packagestore

fn callback(name string, fields map[string]ah.Value) !ah.Value {
	return packagestore.borrowed_binding(name, fields)!
}

fn o(id string) ah.Value { return ah.Value([ah.Value('owner'), ah.Value(id)]) }

fn raw_value(value ah.Value) ah.Value { return ah.Value([ah.Value('value'), value]) }

fn v(value ah.Value) !ah.Value { return o(pooled_literal(raw_value(value))!) }

fn b(hex string) !ah.Value { return o(pooled_literal(ah.Value([ah.Value('bytes'), ah.Value(hex)]))!) }

fn none_value() ah.Value { return ah.Value(json2.Null{}) }

fn invoke_target(target string, args []ah.Value, kwargs map[string]ah.Value) !string {
	result := callback('function', {
		'target': ah.Value(target)
		'call':   ah.Value(true)
		'args':   ah.Value(args)
		'kwargs': ah.Value(kwargs)
		'intern_keywords': ah.Value(true)
	}) or {
		cause := err
		release([target])!
		return cause
	}
	release([target])!
	return result.text()
}

// CPython's literal attribute names are interned. Borrow the exact name object
// declared by the adapter, rather than making a new name for a supplied object.
fn member(id string, name string) !string {
	keys := constant('_SLOT_KEYS')!
	key := callback('function', {
		'name': ah.Value('operator.getitem')
		'call': ah.Value(true)
		'args': ah.Value([o(keys), v(ah.Value(name))!])
	})!.text()
	getattr_ := constant('getattr')!
	result := invoke_target(getattr_, [o(id), o(key)], {}) or {
		cause := err
		release([keys, key])!
		return cause
	}
	release([keys, key])!
	return result
}

fn constant(name string) !string {
	parts := name.split('.')
	mut value := callback('resolve', {
		'name': ah.Value(parts[0])
	})!.text()
	for part in parts[1..] {
		next := member(value, part) or {
			release([value])!
			return err
		}
		release([value])!
		value = next
	}
	return value
}

// The native definitions contain a finite set of scalar/byte literals. Their
// actual CPython objects belong to the module, like co_consts in the original.
fn pooled_literal(operand ah.Value) !string {
 cache := constant('_LITERAL_CACHE')!
 parts := operand.items()
 value := parts[1]
 intern := parts[0].text() == 'value' && value is string && value.len > 0 && value.bytes().all((it >= `a` && it <= `z`) || (it >= `A` && it <= `Z`) || (it >= `0` && it <= `9`) || it == `_`)
 result := callback('literal', {
  'value': operand
  'constant_cache': ah.Value(cache)
  'constant_key': ah.Value(ah.encode(operand))
  'intern': ah.Value(intern)
 }) or { release([cache])!; return err }
 release([cache])!
 return result.text()
}

fn literal(value ah.Value) !string { return pooled_literal(raw_value(value))! }

fn item(id string, key ah.Value) !string {
	return invoke_target(constant('operator.getitem')!, [o(id), key], {})!
}

fn get(id string, key string) !string { return item(id, v(ah.Value(key))!)! }

fn join(id string, path string) !string {
	return invoke_target(constant('operator.truediv')!, [o(id), v(ah.Value(path))!], {})!
}

fn add(id string, value ah.Value) !string {
	return invoke_target(constant('operator.add')!, [o(id), value], {})!
}

fn release(ids []string) ! {
	callback('release', {
		'ids': ah.Value(ids.map(ah.Value(it)))
	})!
}

fn discard(id string) ! { release([id])! }

fn set_item(id string, key ah.Value, value ah.Value) ! {
	discard(invoke_target(constant('operator.setitem')!, [o(id), key, value], {})!)!
}

fn slice(start ah.Value, end ah.Value) !string {
	return invoke_target(constant('slice')!, [start, end], {})!
}

fn set_slice(id string, start ah.Value, end ah.Value, value ah.Value) ! {
	set_item(id, o(slice(start, end)!), value)!
}

fn length(id string) !string { return invoke_target(constant('len')!, [o(id)], {})! }

fn sequence(kind string, values []string) !string {
	return callback('collection', {
		'kind':   ah.Value(kind)
		'values': ah.Value(values.map(ah.Value(it)))
	})!.text()
}

fn detail(cause IError) ah.Value {
	if cause is packagestore.BindingError { return ah.Value(cause.value) }
	return none_value()
}

fn enter(manager string) !string {
	return callback('enter', {
		'owner':   ah.Value(manager)
		'consume': ah.Value(true)
	})!.text()
}

fn exit(manager string, cause ?IError) !bool {
	return callback('exit', {
		'owner': ah.Value(manager)
		'error': if e := cause { detail(e) } else { none_value() }
	})! as bool
}

fn with_manager(manager string, body fn (string) !) ! {
	value := enter(manager)!
	body(value) or {
		cause := err
		if !exit(manager, cause)! { return cause }
		if cause is packagestore.BindingError {
			callback('retire_error', {
				'error': ah.Value(cause.value)
			})!
		}
		return
	}
	exit(manager, none)!
}

fn expect(self string, exception string, body fn () !) ! {
	manager := invoke_target(member(self, 'assertRaises')!, [o(constant(exception)!)], {})!
	with_manager(manager, fn [body] (_ string) ! { body()! })!
	release([manager])!
}

fn subtest(self string, options map[string]ah.Value, body fn () !) ! {
	manager := invoke_target(member(self, 'subTest')!, [], options)!
	with_manager(manager, fn [body] (_ string) ! { body()! })!
	release([manager])!
}

struct Frame {
	pins string
mut:
	names map[string]string
}

fn (mut f Frame) named(name string, value string) !string {
	if old := f.names[name] {
		if old != value && f.names.values().filter(it == old).len == 1 { release([old])! }
	}
	f.names[name] = value
	return value
}

fn (f &Frame) clean() ! {
	mut keep := f.names.values()
	keep << f.pins
	callback('release_since', {
		'checkpoint': ah.Value(0)
		'keep':       ah.Value(keep.map(ah.Value(it)))
	})!
}

// A saved Python traceback must keep the original named fixture objects alive.
// This dictionary lives in the adapter frame; successful calls leave it empty.
fn (f &Frame) pin_failure() ! {
	for name, id in f.names {
		if name.starts_with('tuple-') || name.starts_with('offset-tuple-') { continue }
		set_item(f.pins, v(ah.Value(name))!, o(id))!
	}
}

fn format_value(value string) !string {
	return invoke_target(constant('_format')!, [o(value)], {})!
}

fn formatted_string(parts []string) !string {
	items := sequence('tuple', parts)!
	separator := literal(ah.Value(''))!
	joiner := member(separator, 'join')!
	release([separator])!
	value := invoke_target(joiner, [o(items)], {}) or {
		cause := err
		release(parts)!
		release([items])!
		return cause
	}
	release(parts)!
	release([items])!
	return value
}
