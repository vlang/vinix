// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module ioscontroller

import androidhost as ah
import json2
import packagestore

fn callback(name string, row map[string]ah.Value) !ah.Value {
	return packagestore.borrowed_binding(name, row)!
}

fn o(id string) ah.Value { return ah.Value([ah.Value('owner'), ah.Value(id)]) }

fn raw(value ah.Value) ah.Value { return ah.Value([ah.Value('value'), value]) }

fn none_() ah.Value { return ah.Value(json2.Null{}) }

fn release(ids []string) ! {
	callback('release', {
		'ids': ah.Value(ids.map(ah.Value(it)))
	})!
}

fn resolve(name string) !string {
	return callback('resolve', {
		'name': ah.Value(name)
	})!.text()
}

fn invoke(target string, arguments []ah.Value, options map[string]ah.Value) !string {
	result := callback('function', {
		'target':          ah.Value(target)
		'call':            ah.Value(true)
		'args':            ah.Value(arguments)
		'kwargs':          ah.Value(options)
		'intern_keywords': ah.Value(true)
	}) or {
		cause := err
		release([target])!
		return cause
	}
	release([target])!
	return result.text()
}

fn invoke_owned(target string, arguments []ah.Value, options map[string]ah.Value, consumed []string) !string {
	result := callback('function', {
		'target':          ah.Value(target)
		'call':            ah.Value(true)
		'args':            ah.Value(arguments)
		'kwargs':          ah.Value(options)
		'intern_keywords': ah.Value(true)
	}) or {
		cause := err
		release(consumed)!
		release([target])!
		return cause
	}
	release(consumed)!
	release([target])!
	return result.text()
}

fn literal(value ah.Value) !string {
	cache := resolve('_LITERAL_CACHE')!
	operand := raw(value)
	result := callback('literal', {
		'value':          operand
		'constant_cache': ah.Value(cache)
		'constant_key':   ah.Value(ah.encode(operand))
		'intern':         ah.Value(value is string && value.len > 0 && value.bytes().all((it >= `a` && it <= `z`) || (it >= `A` && it <= `Z`) || (it >= `0` && it <= `9`) || it == `_`))
	}) or {
		release([cache])!
		return err
	}
	release([cache])!
	return result.text()
}

fn v(value ah.Value) !ah.Value { return o(literal(value)!) }

fn bytes_(hex string) !string {
	cache := resolve('_LITERAL_CACHE')!
	operand := ah.Value([ah.Value('bytes'), ah.Value(hex)])
	result := callback('literal', {
		'value':          operand
		'constant_cache': ah.Value(cache)
		'constant_key':   ah.Value(ah.encode(operand))
	}) or {
		release([cache])!
		return err
	}
	release([cache])!
	return result.text()
}

fn item(id string, key ah.Value) !string {
	return invoke(resolve('operator.getitem')!, [o(id), key], {})!
}

fn get(id string, key string) !string { return item(id, v(ah.Value(key))!)! }

fn member(id string, name string) !string {
	keys := resolve('_SLOT_KEYS')!
	key := get(keys, name) or {
		release([keys])!
		return err
	}
	target := resolve('_ATTRIBUTE') or {
		release([key, keys])!
		return err
	}
	result := invoke(target, [o(id), o(key)], {}) or {
		release([key, keys])!
		return err
	}
	release([key, keys])!
	return result
}

__global current_builtins string

fn global(name string) !string {
	// These helpers model Python intrinsic operators, not source LOAD_GLOBAL.
	if name.starts_with('operator.') { return resolve(name)! }
	parts := name.split('.')
	key := literal(ah.Value(parts[0]))!
	result := callback('load_global', {
		'key':      ah.Value(key)
		'builtins': ah.Value(current_builtins)
	}) or {
		release([key])!
		return err
	}
	release([key])!
	mut id := result.text()
	for part in parts[1..] {
		next := member(id, part) or {
			release([id])!
			return err
		}
		release([id])!
		id = next
	}
	return id
}

fn call(name string, arguments ...ah.Value) !string { return invoke(global(name)!, arguments, {})! }

fn truth(id string) !bool {
	target := resolve('_TRUTH')!
	result := callback('function', {
		'target': ah.Value(target)
		'call':   ah.Value(true)
		'args':   ah.Value([o(id)])
		'data':   ah.Value(true)
	}) or {
		release([target])!
		return err
	}
	release([target])!
	return result as bool
}

fn formatted(id string, repr_ bool) !string {
	return call(if repr_ { '_REPR' } else { '_FORMAT' }, o(id))!
}

fn concatenate(parts []string) !string {
	values := call('_tuple', ...parts.map(o(it))) or {
		release(parts.reverse())!
		return err
	}
	empty := literal(ah.Value('')) or {
		release([values])!
		release(parts.reverse())!
		return err
	}
	target := member(empty, 'join') or {
		release([empty, values])!
		release(parts.reverse())!
		return err
	}
	release([empty])!
	result := invoke(target, [o(values)], {}) or {
		release([values])!
		release(parts.reverse())!
		return err
	}
	release([values])!
	release(parts.reverse())!
	return result
}

fn checkpoint() !ah.Value { return callback('checkpoint', {})! }

fn clean_since(start ah.Value, keep []string) ! {
	callback('release_since', {
		'checkpoint': start
		'keep':       ah.Value(keep.map(ah.Value(it)))
	})!
}

struct Frame {
	start ah.Value
	pins  string
	scope string
mut:
	names map[string]string
}

fn (mut f Frame) named(name string, id string) ! {
	release([call('operator.setitem', o(f.scope), v(ah.Value(name))!, o(id))!])!
	if old := f.names[name] {
		f.names[name] = id
		release([old])!
	} else {
		f.names[name] = id
	}
}

fn (mut f Frame) load(name string) !string {
	// LOAD_FAST owns a separate expression reference to the current named value.
	return get(f.scope, name)!
}

fn (f &Frame) failed() ! {
	release([call('_pin_scope', o(f.pins), o(f.scope))!])!
	clean_since(f.start, [f.pins, f.scope])!
}

struct Temps {
mut:
	ids []string
}

fn (mut t Temps) hold(id string) string {
	t.ids << id
	return id
}

fn (mut t Temps) take(id string) string {
	for i, value in t.ids {
		if value == id {
			t.ids.delete(i)
			break
		}
	}
	return id
}

fn (mut t Temps) drop(id string) ! {
	t.take(id)
	release([id])!
}

fn (mut t Temps) clear() ! {
	for t.ids.len > 0 {
		id := t.ids.pop()
		release([id])!
	}
}

fn operation(name string, args []string) !string {
	return invoke(resolve('operator.' + name)!, args.map(o(it)), {})!
}

fn set_attribute(owner string, name string, id string) ! {
	release([invoke(resolve('_SET_ATTRIBUTE')!, [o(owner), v(ah.Value(name))!, o(id)], {})!])!
}
