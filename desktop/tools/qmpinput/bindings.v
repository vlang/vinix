// SPDX-License-Identifier: GPL-2.0-or-later
module qmpinput

import androidhost as ah
import packagestore

fn callback(name string, args map[string]ah.Value) !ah.Value {
	return packagestore.borrowed_binding(name, args)!
}

fn v(value ah.Value) ah.Value { return ah.Value([ah.Value('value'), value]) }

fn o(id string) ah.Value { return ah.Value([ah.Value('owner'), ah.Value(id)]) }

fn s(value string) ah.Value { return v(ah.Value(value)) }

fn n(value int) ah.Value { return v(ah.Value(value)) }

fn release(ids ...string) ! {
	callback('release', {
		'ids': ah.Value(ids.map(ah.Value(it)))
	})!
}

fn resolve(name string) !string {
	return callback('resolve', {
		'name': ah.Value(name)
	})!.text()
}

fn attr(id string, name string) !string {
	return callback('attribute', {
		'owner': ah.Value(id)
		'name':  ah.Value(name)
	})!.text()
}

fn raw(target string, args []ah.Value, kwargs map[string]ah.Value) !string {
	return callback('function', {
		'target': ah.Value(target)
		'args':   ah.Value(args)
		'kwargs': ah.Value(kwargs)
		'call':   ah.Value(true)
	})!.text()
}

fn invoke(target string, args []ah.Value, kwargs map[string]ah.Value, temporary []string) !string {
	result := raw(target, args, kwargs) or {
		cause := err
		release(...temporary)!
		release(target)!
		return cause
	}
	release(...temporary)!
	release(target)!
	return result
}

fn call(name string, args []ah.Value) !string { return invoke(resolve(name)!, args, {}, [])! }

fn method(id string, name string, args []ah.Value) !string {
	return invoke(attr(id, name)!, args, {}, [])!
}

fn literal(value ah.Value) !string {
	return callback('literal', {
		'value': v(value)
	})!.text()
}

fn truth(id string) !bool {
	return callback('function', {
		'name': ah.Value('builtins.bool')
		'args': ah.Value([o(id)])
		'data': ah.Value(true)
		'call': ah.Value(true)
	})! as bool
}

fn test(id string) !bool {
	result := truth(id) or {
		cause := err
		release(id)!
		return cause
	}
	release(id)!
	return result
}

fn set_attr(id string, name string, value string) ! {
	callback('set_attribute', {
		'owner': ah.Value(id)
		'name':  ah.Value(name)
		'value': o(value)
	})!
}

fn binary(name string, left string, right ah.Value) !string {
	return call('operator.' + name, [o(left), right])!
}

fn list(ids []string) !string {
	return callback('collection', {
		'kind':   ah.Value('list')
		'values': ah.Value(ids.map(ah.Value(it)))
	})!.text()
}

fn dictionary(names []string, values []ah.Value) !string {
	id := literal(ah.Value(map[string]ah.Value{}))!
	for index, name in names {
		release(call('operator.setitem', [o(id), s(name), values[index]])!)!
	}
	return id
}

fn press(name string, down ah.Value) !string {
	key := dictionary(['type', 'data'], [s('qcode'), o(name)])!
	data := dictionary(['down', 'key'], [down, o(key)])!
	release(key)!
	event := dictionary(['type', 'data'], [s('key'), o(data)])!
	release(data)!
	return event
}

fn named_press(name string, down bool) !string {
	id := literal(ah.Value(name))!
	result := press(id, v(ah.Value(down))) or {
		release(id)!
		return err
	}
	release(id)!
	return result
}

fn discarded(id string) ! { release(id)! }

fn next(iterator string) !ah.Value {
	return callback('next', {
		'owner': ah.Value(iterator)
	})!
}

fn iterate(value string) !string { return call('builtins.iter', [o(value)])! }

fn checkpoint() !ah.Value { return callback('checkpoint', {})! }

fn sweep(mark ah.Value, keep []string) ! {
	callback('release_since', {
		'checkpoint': mark
		'keep':       ah.Value(keep.map(ah.Value(it)))
	})!
}

fn sleep(value ah.Value) ! { discarded(call('time.sleep', [value])!)! }
