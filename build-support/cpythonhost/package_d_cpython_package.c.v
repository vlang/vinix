// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

import androidhost as ah
import json2

fn C.PyObject_GetItem(voidptr, voidptr) voidptr
fn C.PyList_Append(voidptr, voidptr) i32
fn C.PyUnicode_CheckExact(voidptr) i32
fn C.PyDict_DelItemString(voidptr, &char) i32
fn C.PyDict_SetItem(voidptr, voidptr, voidptr) i32
fn C.PyObject_GetAttr(voidptr, voidptr) voidptr
fn C.PyObject_SetAttr(voidptr, voidptr, voidptr) i32

@[c_extern]
__global C.PyExc_KeyError voidptr

fn package_key_error(key string) {
	value := py_string(key)
	C.PyErr_SetObject(unsafe { voidptr(C.PyExc_KeyError) }, value)
	drop(value)
}

fn package_none(value voidptr) bool {
	none_value := py_none()
	result := value == none_value
	drop(none_value)
	return result
}

struct PackageOwner {
	id string
mut:
	manager        voidptr
	method         voidptr
	kwargs         voidptr
	condition      voidptr
	function       voidptr
	methods        voidptr
	active         bool = true
	entered        string
	native_manager bool
}

struct PackageSession {
mut:
	context       &Context
	stack         voidptr
	errors_py     voidptr
	key           u64
	owners        map[string]&PackageOwner
	entered       map[string]string
	closers       map[string]string
	serial        int
	direct_result voidptr
	lookup        voidptr
	lookup_ids    map[string]bool
}

__global package_sessions = map[u64]&PackageSession{}
__global package_next u64 = 1

fn py_attr(p voidptr, name string) voidptr {
	key := py_string(name)
	result := C.PyObject_GetAttr(p, key)
	drop(key)
	return result
}

fn package_python(value ah.Value) voidptr {
	if value is map[string]ah.Value {
		result := C.PyDict_New()
		for name, item in value {
			key := py_string(name)
			entry := package_python(item)
			if entry == unsafe { nil } {
				drop(key)
				drop(result)
				return unsafe { nil }
			}
			status := C.PyDict_SetItem(result, key, entry)
			drop(key)
			drop(entry)
			if status != 0 {
				drop(result)
				return unsafe { nil }
			}
		}
		return result
	}
	if value is []ah.Value {
		result := C.PyList_New(value.len)
		for i, item in value {
			entry := package_python(item)
			if entry == unsafe { nil } {
				drop(result)
				return unsafe { nil }
			}
			C.PyList_SetItem(result, i, entry)
		}
		return result
	}
	return to_python(value)
}

fn (s &PackageSession) operand(value ah.Value) voidptr {
	parts := value.items()
	if parts[0].text() == 'owner' { return own(s.context.borrowed(parts[1].text())) }
	if parts[0].text() == 'bytes' { return s.context.operand(value) }
	return package_python(parts[1])
}

fn (s &PackageSession) arguments(values []ah.Value) voidptr {
	result := C.PyTuple_New(values.len)
	for i, value in values {
		entry := s.operand(value)
		if entry == unsafe { nil } {
			drop(result)
			return unsafe { nil }
		}
		C.PyTuple_SetItem(result, i, entry)
	}
	return result
}

fn (s &PackageSession) keywords(values map[string]ah.Value) voidptr {
	result := C.PyDict_New()
	for name, value in values {
		key := py_string(name)
		entry := s.operand(value)
		if entry == unsafe { nil } {
			drop(key)
			drop(result)
			return unsafe { nil }
		}
		status := C.PyDict_SetItem(result, key, entry)
		drop(key)
		drop(entry)
		if status != 0 {
			drop(result)
			return unsafe { nil }
		}
	}
	return result
}

fn py_item(p voidptr, name string) voidptr {
	key := py_string(name)
	result := C.PyObject_GetItem(p, key)
	drop(key)
	return result
}

fn py_call(p voidptr, values []voidptr) voidptr {
	args := C.PyTuple_New(values.len)
	for i, value in values { C.PyTuple_SetItem(args, i, own(value)) }
	result := C.PyObject_Call(p, args, unsafe { nil })
	drop(args)
	return result
}

fn py_method(p voidptr, name string, values []voidptr) voidptr {
	target := py_attr(p, name)
	if target == unsafe { nil } { return unsafe { nil } }
	result := py_call(target, values)
	drop(target)
	return result
}

fn py_truth(p voidptr) bool { return p != unsafe { nil } && C.PyObject_IsTrue(p) != 0 }

fn (s &PackageSession) namespace_get(name string, fallback voidptr) voidptr {
	target := py_attr(s.context.namespace, 'get')
	if target == unsafe { nil } { return unsafe { nil } }
	key := py_string(name)
	result := py_call(target, [key, fallback])
	drop(key)
	drop(target)
	return result
}

fn (s &PackageSession) resolve(name string) voidptr {
	parts := name.split('.')
	mut fallback := py_attr(s.context.builtins, parts[0])
	if fallback == unsafe { nil } {
		if C.PyErr_GivenExceptionMatches(C.PyErr_Occurred(), unsafe { voidptr(C.PyExc_AttributeError) }) == 0 {
			return fallback
		}
		C.PyErr_Clear()
		fallback = py_none()
	}
	mut result := s.namespace_get(parts[0], fallback)
	drop(fallback)
	if result == unsafe { nil } { return result }
	if parts[0] in ['builtins', 'operator'] {
		drop(result)
		result = own(if parts[0] == 'builtins' { s.context.builtins } else { s.context.operator })
	}
	for part in parts[1..] {
		next := py_attr(result, part)
		drop(result)
		result = next
		if result == unsafe { nil } { break }
	}
	return result
}

fn (mut s PackageSession) retained(p voidptr) ah.Value {
	return if p == unsafe { nil } { null() } else { ah.Value(s.context.retain(p)) }
}

fn (mut s PackageSession) release_id(id string) {
	if id in s.closers { return }
	if key := s.entered[id] {
		if !s.owners[key].native_manager { return }
	}
	for _, key in s.entered { if s.owners[key].entered == id { return } }
	if s.lookup != unsafe { nil } && id in s.lookup_ids {
		for manager in s.context.managers {
			if manager.active && manager.entered == id { return }
		}
		s.context.objects.delete(id)
		s.lookup_ids.delete(id)
		unsafe { C.PyDict_DelItemString(s.lookup, id.str) }
		return
	}
	s.context.release(id)
}

// Rich result keys can call back into this session during dictionary lookup.
// Transfer each existing table reference to the live CPython dictionary for
// that lookup, then restore table ownership before releasing the dictionary.
// There is still exactly one table reference per object at callback boundaries.
fn (mut s PackageSession) sync_lookup() {
	if s.lookup == unsafe { nil } { return }
	for id, value in s.context.objects {
		if id in s.lookup_ids { continue }
		if unsafe { C.PyDict_SetItemString(s.lookup, id.str, value) } != 0 { return }
		s.lookup_ids[id] = true
		drop(value)
	}
}

fn (mut s PackageSession) lookup_result(key voidptr) voidptr {
	s.lookup = C.PyDict_New()
	if s.lookup == unsafe { nil } { return unsafe { nil } }
	s.sync_lookup()
	result := if pending_error() { unsafe { nil } } else { C.PyObject_GetItem(s.lookup, key) }
	// Preserve a pending hash/equality error while references are transferred.
	mut kind := voidptr(0)
	mut error := voidptr(0)
	mut traceback := voidptr(0)
	C.PyErr_Fetch(&kind, &error, &traceback)
	for id, value in s.context.objects {
		if id in s.lookup_ids { own(value) }
	}
	lookup := s.lookup
	s.lookup = unsafe { nil }
	s.lookup_ids.clear()
	drop(lookup)
	C.PyErr_Restore(kind, error, traceback)
	return result
}

fn (s &PackageSession) require_id(id string) bool {
	if id in s.context.objects { return true }
	package_key_error(id)
	return false
}

fn (s &PackageSession) check_ids(row map[string]ah.Value) bool {
	for key in ['owner', 'target', 'kwargs_owner', 'class'] {
		if key in row && !s.require_id(row[key].text()) { return false }
	}
	for key in ['args', 'value'] {
		if key !in row { continue }
		values := if key == 'value' { [row[key]] } else { row[key].items() }
		for value in values {
			parts := value.items()
			if parts.len > 1 && parts[0].text() == 'owner' && !s.require_id(parts[1].text()) {
				return false
			}
		}
	}
	if 'kwargs' in row {
		for _, value in ah.field(row, 'kwargs').object() {
			parts := value.items()
			if parts.len > 1 && parts[0].text() == 'owner' && !s.require_id(parts[1].text()) {
				return false
			}
		}
	}
	if 'values' in row {
		for id in ah.field(row, 'values').items() { if !s.require_id(id.text()) { return false } }
	}
	return true
}

fn (mut s PackageSession) add_owner(id string, row map[string]ah.Value, entered string) voidptr {
	mut kwargs := C.PyDict_New()
	if 'kwargs' in row {
		drop(kwargs)
		kwargs = s.keywords(ah.field(row, 'kwargs').object())
	}
	method := if 'method' in row { to_python(ah.field(row, 'method')) } else { py_none() }
	function := if 'function' in row {
		s.resolve(ah.field(row, 'function').text())
	} else {
		own(method)
	}
	if function == unsafe { nil } {
		drop(kwargs)
		drop(method)
		return unsafe { nil }
	}
	owner := &PackageOwner{
		id:             id
		manager:        if 'native_manager' in row {
			unsafe { nil }
		} else {
			own(s.context.borrowed(id))
		}
		method:         function
		kwargs:         kwargs
		condition:      if 'condition' in row {
			to_python(ah.field(row, 'condition'))
		} else {
			py_none()
		}
		function:       if 'function_name' in row {
			to_python(ah.field(row, 'function_name'))
		} else {
			py_none()
		}
		methods:        if 'own_methods' in row {
			to_python(ah.field(row, 'own_methods'))
		} else {
			py_none()
		}
		entered:        entered
		native_manager: 'native_manager' in row
	}
	drop(method)
	key := s.serial.str()
	s.serial++
	s.owners[key] = owner
	if owner.native_manager { s.entered[id] = key } else { s.closers[id] = key }
	factory := unsafe { C.PyDict_GetItemString(s.context.syntax, c'owner') }
	token := C.PyLong_FromLongLong(i64(s.key))
	ident := py_string(key)
	bound := py_call(factory, [token, ident])
	drop(token)
	drop(ident)
	if bound == unsafe { nil } { return bound }
	result := py_method(s.stack, 'push', [bound])
	drop(bound)
	return result
}

fn (mut s PackageSession) exit_owner(key string, details voidptr) voidptr {
	mut owner := s.owners[key] or { return py_none() }
	if !owner.active { return to_python(ah.Value(false)) }
	owner.active = false
	if owner.native_manager { return s.exit_native(owner.id, details) }
	if !package_none(owner.methods) {
		iterator := C.PyObject_GetIter(owner.methods)
		if iterator == unsafe { nil } { return unsafe { nil } }
		defer { drop(iterator) }
		for {
			path := C.PyIter_Next(iterator)
			if path == unsafe { nil } { break }
			parts := string_value(path).split('.')
			drop(path)
			mut target := own(owner.manager)
			for part in parts {
				next := py_attr(target, part)
				drop(target)
				target = next
				if target == unsafe { nil } { return target }
			}
			result := py_call(target, []voidptr{})
			drop(target)
			if result == unsafe { nil } { return result }
			drop(result)
		}
		return if pending_error() { unsafe { nil } } else { to_python(ah.Value(false)) }
	}
	method_truth := py_truth(owner.method)
	if pending_error() { return unsafe { nil } }
	function_truth := if method_truth { false } else { py_truth(owner.function) }
	if pending_error() { return unsafe { nil } }
	if method_truth || function_truth {
		condition_truth := py_truth(owner.condition)
		if pending_error() { return unsafe { nil } }
		if condition_truth {
			name := string_value(owner.condition)
			result := py_method(owner.manager, name, []voidptr{})
			if result == unsafe { nil } { return result }
			ready := py_truth(result)
			drop(result)
			if pending_error() { return unsafe { nil } }
			if !ready { return to_python(ah.Value(false)) }
		}
		callable := C.PyCallable_Check(owner.method) != 0
		has_function := py_truth(owner.function)
		if pending_error() { return unsafe { nil } }
		target := if has_function {
			s.resolve(string_value(owner.function))
		} else if callable {
			own(owner.method)
		} else {
			py_attr(owner.manager, string_value(owner.method))
		}
		if target == unsafe { nil } { return target }
		has_function_arg := py_truth(owner.function)
		if pending_error() {
			drop(target)
			return unsafe { nil }
		}
		callable_arg := if has_function_arg { false } else { C.PyCallable_Check(owner.method) != 0 }
		args := C.PyTuple_New(if has_function_arg || callable_arg { 1 } else { 0 })
		if C.PyTuple_Size(args) == 1 { C.PyTuple_SetItem(args, 0, own(owner.manager)) }
		result := C.PyObject_Call(target, args, owner.kwargs)
		drop(args)
		drop(target)
		if result == unsafe { nil } { return result }
		drop(result)
		return to_python(ah.Value(false))
	}
	target := py_attr(owner.manager, '__exit__')
	if target == unsafe { nil } { return target }
	result := C.PyObject_Call(target, details, unsafe { nil })
	drop(target)
	return result
}

fn (mut s PackageSession) consume_owner(key string, record ah.Value) ah.Value {
	mut native_owner := s.owners[key]
	if native_owner.native_manager {
		native_owner.active = false
		return s.context.primitive('exit', {
			'owner': ah.Value(native_owner.id)
			'error': record
		})
	}
	mut details := C.PyTuple_New(3)
	mut before := handled()
	if record !is json2.Null {
		error := s.context.errors[int(ah.field(record.object(), 'binding_error') as int)]
		error.activate()
		C.PyTuple_SetItem(details, 0, own(error.kind))
		C.PyTuple_SetItem(details, 1, own(error.value))
		tb := error.tb()
		C.PyTuple_SetItem(details, 2, if tb == unsafe { nil } { py_none() } else { tb })
	} else {
		for i in 0 .. 3 { C.PyTuple_SetItem(details, i, py_none()) }
	}
	result := s.exit_owner(key, details)
	drop(details)
	truth := if result == unsafe { nil } {
		false
	} else if record !is json2.Null {
		py_truth(result)
	} else {
		false
	}
	drop(result)
	mut owner := s.owners[key]
	drop(owner.manager)
	owner.manager = unsafe { nil }
	drop(owner.method)
	owner.method = unsafe { nil }
	drop(owner.kwargs)
	owner.kwargs = unsafe { nil }
	before.activate()
	before.discard()
	return ah.Value(truth)
}

fn (mut s PackageSession) function(row map[string]ah.Value) ah.Value {
	target := if 'target' in row {
		own(s.context.borrowed(ah.field(row, 'target').text()))
	} else if 'owner' in row {
		py_attr(s.context.borrowed(ah.field(row, 'owner').text()), ah.field(row, 'name').text())
	} else {
		s.resolve(ah.field(row, 'name').text())
	}
	if target == unsafe { nil } { return null() }
	defer { drop(target) }
	data := 'data' in row && ah.field(row, 'data') as bool
	if C.PyCallable_Check(target) == 0 && !('call' in row && ah.field(row, 'call') as bool) {
		if data {
			s.direct_result = own(target)
			return null()
		}
		ident := s.context.retain(own(target))
		if 'own_methods' in row {
			pushed := s.add_owner(ident, row, '')
			drop(pushed)
		}
		return ah.Value(ident)
	}
	args := s.arguments(if 'args' in row {
		ah.field(row, 'args').items()
	} else {
		[]ah.Value{}
	})
	if args == unsafe { nil } { return null() }
	defer { drop(args) }
	kwargs := s.keywords(if 'kwargs' in row {
		ah.field(row, 'kwargs').object()
	} else {
		map[string]ah.Value{}
	})
	if kwargs == unsafe { nil } { return null() }
	defer { drop(kwargs) }
	result := if 'kwargs_owner' in row {
		helper := unsafe { C.PyDict_GetItemString(s.context.syntax, c'double_kwargs') }
		joined := C.PyTuple_New(4)
		C.PyTuple_SetItem(joined, 0, own(target))
		C.PyTuple_SetItem(joined, 1, own(args))
		C.PyTuple_SetItem(joined, 2, own(kwargs))
		C.PyTuple_SetItem(joined, 3, own(s.context.borrowed(ah.field(row, 'kwargs_owner').text())))
		value := C.PyObject_Call(helper, joined, unsafe { nil })
		drop(joined)
		value
	} else {
		C.PyObject_Call(target, args, kwargs)
	}
	if result == unsafe { nil } { return null() }
	if data {
		s.direct_result = result
		return null()
	}
	ident := s.context.retain(result)
	if 'own_methods' in row {
		pushed := s.add_owner(ident, row, '')
		drop(pushed)
	}
	return ah.Value(ident)
}

fn (mut s PackageSession) enter(row map[string]ah.Value) ah.Value {
	id := ah.field(row, 'owner').text()
	manager := own(s.context.borrowed(id))
	target := s.context.special(manager, '__enter__')
	if target == unsafe { nil } {
		drop(manager)
		return null()
	}
	exit_target := s.context.special(manager, '__exit__')
	if exit_target == unsafe { nil } {
		drop(target)
		drop(manager)
		return null()
	}
	consume := ah.field(row, 'consume')
	if consume is bool && consume { s.release_id(id) }
	drop(manager)
	args := C.PyTuple_New(0)
	value := C.PyObject_Call(target, args, unsafe { nil })
	drop(args)
	drop(target)
	if value == unsafe { nil } {
		drop(exit_target)
		return null()
	}
	entered := s.context.retain(value)
	s.context.managers << Manager{ id: id, entered: entered, exit_target: exit_target }
	return ah.Value(entered)
}

fn (mut s PackageSession) primitive(name string, row map[string]ah.Value) ah.Value {
	if name !in ['release', 'release_since', 'retire_error', 'checkpoint', 'exit', 'close', 'transfer'] && !s.check_ids(row) {
		return null()
	}
	match name {
		'resolve' { return s.retained(s.resolve(ah.field(row, 'name').text())) }
		'release' {
			for id in ah.field(row, 'ids').items() { s.release_id(id.text()) }
			return null()
		}
		'release_since' {
			start := int(ah.field(row, 'checkpoint') as int)
			keep := if 'keep' in row {
				ah.field(row, 'keep').items().map(it.text())
			} else {
				[]string{}
			}
			for id in s.context.objects.keys() {
				if id.int() >= start && id !in keep { s.release_id(id) }
			}
			return null()
		}
		'retire_error' {
			index := int(ah.field(ah.field(row, 'error').object(), 'binding_error') as int)
			s.context.errors[index].discard()
			s.context.errors[index] = Exception{}
			C.PyList_SetItem(s.errors_py, index, py_none())
			return null()
		}
		'function' { return s.function(row) }
		'enter' {
			id := ah.field(row, 'owner').text()
			value := s.enter(row)
			if pending_error() { return null() }
			entered := value.text()
			pushed := s.add_owner(id, {
				'native_manager': ah.Value(true)
			}, entered)
			drop(pushed)
			return value
		}
		'own' {
			pushed := s.add_owner(ah.field(row, 'owner').text(), row, '')
			drop(pushed)
			return null()
		}
		'exit', 'close' {
			id := ah.field(row, 'owner').text()
			key := if name == 'exit' {
				s.entered[id] or {
					package_key_error(id)
					return null()
				}
			} else {
				s.closers[id] or {
					package_key_error(id)
					return null()
				}
			}
			if name == 'exit' { s.entered.delete(id) } else { s.closers.delete(id) }
			return s.consume_owner(key, ah.field(row, 'error'))
		}
		'transfer' {
			id := ah.field(row, 'owner').text()
			key := s.closers[id] or {
				package_key_error(id)
				return null()
			}
			s.closers.delete(id)
			s.owners[key].active = false
			return null()
		}
		'error_attribute' {
			index := int(ah.field(ah.field(row, 'error').object(), 'binding_error') as int)
			return s.retained(py_attr(s.context.errors[index].value, ah.field(row, 'name').text()))
		}
		'unbound_local' {
			target := unsafe { C.PyDict_GetItemString(s.context.syntax, c'unbound') }
			arg := py_string(ah.field(row, 'name').text())
			result := py_call(target, [arg])
			drop(arg)
			drop(result)
			return null()
		}
		'collection' {
			values := ah.field(row, 'values').items()
			entries := C.PyList_New(values.len)
			for i, id in values { C.PyList_SetItem(entries, i, own(s.context.borrowed(id.text()))) }
			kind := ah.field(row, 'kind').text()
			if kind !in ['list', 'tuple', 'set'] {
				drop(entries)
				package_key_error(kind)
				return null()
			}
			target := py_attr(s.context.builtins, kind)
			if target == unsafe { nil } {
				drop(entries)
				return null()
			}
			result := py_call(target, [entries])
			drop(entries)
			drop(target)
			return s.retained(result)
		}
		'raise' {
			kind := if 'args' in row {
				s.resolve(ah.field(row, 'kind').text())
			} else {
				mut fallback := py_attr(s.context.builtins, ah.field(row, 'kind').text())
				if fallback == unsafe { nil } {
					if C.PyErr_GivenExceptionMatches(C.PyErr_Occurred(), unsafe { voidptr(C.PyExc_AttributeError) }) == 0 {
						return null()
					}
					C.PyErr_Clear()
					fallback = py_none()
				}
				value := s.namespace_get(ah.field(row, 'kind').text(), fallback)
				drop(fallback)
				value
			}
			if kind == unsafe { nil } { return null() }
			args := if 'args' in row {
				s.arguments(ah.field(row, 'args').items())
			} else {
				s.arguments([ah.Value([ah.Value('value'), ah.field(row, 'message')])])
			}
			if args == unsafe { nil } {
				drop(kind)
				return null()
			}
			cause := C.PyObject_Call(kind, args, unsafe { nil })
			drop(args)
			drop(kind)
			if cause == unsafe { nil } { return null() }
			record := ah.field(row, 'cause')
			if record is json2.Null {
				target := unsafe { C.PyDict_GetItemString(s.context.syntax, c'raise') }
				result := py_call(target, [cause])
				drop(cause)
				drop(result)
				return null()
			}
			error := own(s.context.errors[int(ah.field(record.object(), 'binding_error') as int)].value)
			direct := 'direct_cause' in row && ah.field(row, 'direct_cause') as bool
			target := unsafe {
				C.PyDict_GetItemString(s.context.syntax, if direct {
					c'raise_from'
				} else {
					c'raise_from_handled'
				})
			}
			result := py_call(target, [cause, error])
			drop(cause)
			drop(error)
			drop(result)
			return null()
		}
		'literal' { return s.retained(s.operand(ah.field(row, 'value'))) }
		'attribute' {
			return s.retained(py_attr(s.context.borrowed(ah.field(row, 'owner').text()),
				ah.field(row, 'name').text()))
		}
		'set_attribute' {
			value := s.operand(ah.field(row, 'value'))
			if value == unsafe { nil } { return null() }
			name_ := py_string(ah.field(row, 'name').text())
			C.PyObject_SetAttr(s.context.borrowed(ah.field(row, 'owner').text()), name_, value)
			drop(name_)
			drop(value)
			return null()
		}
		'checkpoint', 'next', 'unpack_pair', 'error_object',
		'exception_matches' {
			return s.context.primitive(name, row)
		}
		else {
			package_error('unknown package-store library call: ' + name)
			return null()
		}
	}
}

fn (mut s PackageSession) callback(name string, row map[string]ah.Value) !ah.Value {
	if name == 'active_error' {
		value := ah.field(row, 'error')
		s.context.active = if value is json2.Null {
			-1
		} else {
			int(ah.field(value.object(), 'binding_error') as int)
		}
		return null()
	}
	before := handled()
	if s.context.active < 0 {
		s.context.incoming.activate()
	} else {
		s.context.errors[s.context.active].activate()
	}
	check := name !in ['release', 'release_since', 'exit', 'close', 'retire_error']
	result := if check && C.PyErr_CheckSignals() != 0 { null() } else { s.primitive(name, row) }
	s.sync_lookup()
	failure := if pending_error() { caught() } else { Exception{} }
	if failure.kind != unsafe { nil } {
		failure.activate()
		record := s.context.failure(failure)
		before.activate()
		before.discard()
		return record
	}
	before.activate()
	before.discard()
	return result
}

fn package_error(message string) voidptr {
	module := C.PyImport_ImportModule(c'builtins')
	kind := C.PyObject_GetAttrString(module, c'RuntimeError')
	drop(module)
	text := py_string(message)
	C.PyErr_SetObject(kind, text)
	drop(text)
	drop(kind)
	return unsafe { nil }
}

pub fn package_entry(operation &char, key u64, first voidptr, second voidptr) voidptr {
	C.GC_allow_register_threads()
	mut registered := false
	if C.GC_thread_is_registered() == 0 {
		mut stack_base := C.GC_stack_base{}
		if C.GC_get_stack_base(&stack_base) != 0 { return C.PyErr_NoMemory() }
		registered = C.GC_register_my_thread(&stack_base) == 0
		if !registered { return C.PyErr_NoMemory() }
	}
	defer { if registered { C.GC_unregister_my_thread() } }
	name := unsafe { operation.vstring() }
	if name == 'begin' {
		syntax := C.PyTuple_GetItem(second, 1)
		args := C.PyTuple_GetItem(second, 0)
		mut context := begin(first, syntax)
		factory := unsafe { C.PyDict_GetItemString(syntax, c'stack') }
		stack := py_call(factory, []voidptr{})
		if stack == unsafe { nil } { return context.native_error('') }
		serial := package_next
		package_next++
		mut session := &PackageSession{ context: context, stack: stack, errors_py: C.PyList_New(0), key: serial }
		package_sessions[serial] = session
		mut ids := []ah.Value{}
		for i in 0 .. int(C.PyTuple_Size(args)) {
			ids << ah.Value(context.retain(own(C.PyTuple_GetItem(args, i))))
		}
		row := C.PyTuple_New(3)
		C.PyTuple_SetItem(row, 0, C.PyLong_FromLongLong(i64(serial)))
		C.PyTuple_SetItem(row, 1, to_python(ah.Value(ids)))
		C.PyTuple_SetItem(row, 2, own(session.errors_py))
		C.PyThread_tss_set(cpython_context_tss, context.previous)
		return row
	}
	mut session := package_sessions[key] or { return package_error('closed native package session') }
	previous := C.PyThread_tss_get(cpython_context_tss)
	C.PyThread_tss_set(cpython_context_tss, session.context)
	defer { C.PyThread_tss_set(cpython_context_tss, previous) }
	match name {
		'primitive' {
			result := session.callback(string_value(first), package_row(from_python(second)).object()) or {
				if err is Failure {
					index := int(ah.field(err.value, 'binding_error') as int)
					session.context.errors[index].restore()
					return unsafe { nil }
				}
				return package_error(err.msg())
			}
			if session.direct_result != unsafe { nil } {
				value := session.direct_result
				session.direct_result = unsafe { nil }
				return value
			}
			return to_python(result)
		}
		'result' {
			if package_none(first) { return py_none() }
			if C.PyUnicode_CheckExact(first) != 0 {
				id := string_value(first)
				if !session.require_id(id) { return unsafe { nil } }
				return own(session.context.borrowed(id))
			}
			return session.lookup_result(first)
		}
		'owner_exit' { return session.exit_owner(string_value(first), second) }
		'flags' { return session.flags(first) }
		'cleanup' {
			target := py_attr(session.stack, '__exit__')
			if target == unsafe { nil } { return target }
			result := C.PyObject_Call(target, first, unsafe { nil })
			drop(target)
			return result
		}
		'finish' {
			package_sessions.delete(key)
			for _, mut owner in session.owners {
				drop(owner.manager)
				owner.manager = unsafe { nil }
				drop(owner.method)
				owner.method = unsafe { nil }
				drop(owner.kwargs)
				owner.kwargs = unsafe { nil }
				drop(owner.condition)
				owner.condition = unsafe { nil }
				drop(owner.function)
				owner.function = unsafe { nil }
				drop(owner.methods)
				owner.methods = unsafe { nil }
			}
			drop(session.stack)
			drop(session.errors_py)
			return session.context.finish(py_none(), -1)
		}
		else { return package_error('unsupported native package operation: ' + name) }
	}
}

fn C.PyErr_NoMemory() voidptr
fn C.GC_thread_is_registered() i32
fn C.GC_allow_register_threads()
fn C.GC_get_stack_base(voidptr) i32
fn C.GC_register_my_thread(voidptr) i32
fn C.GC_unregister_my_thread() i32

fn package_row(value ah.Value) ah.Value {
	return match value {
		i64 {
			if value >= -2147483648 && value <= 2147483647 {
				ah.Value(int(value))
			} else {
				ah.Value(value)
			}
		}
		[]ah.Value { ah.Value(value.map(package_row(it))) }
		map[string]ah.Value {
			mut result := map[string]ah.Value{}
			for name, item in value { result[name] = package_row(item) }
			ah.Value(result)
		}
		else { value }
	}
}

fn (s &PackageSession) flags(cause voidptr) voidptr {
	mut result := map[string]ah.Value{}
	for row in [['os_error', 'OSError'], ['missing', 'FileNotFoundError'],
		['tar_error', 'tarfile.TarError'], ['overlay', 'OverlayError'],
		['source', 'SourceSnapshotError'], ['value_error', 'ValueError'],
		['called_process', 'subprocess.CalledProcessError'], ['shutil_error', 'shutil.Error'],
		['clipboard', 'ClipboardError'], ['interrupt', 'KeyboardInterrupt'],
		['exception', 'Exception']] {
		parts := row[1].split('.')
		mut kind := voidptr(0)
		if row[0] in ['overlay', 'source', 'clipboard'] {
			fallback := C.PyTuple_New(0)
			kind = s.namespace_get(parts[0], fallback)
			drop(fallback)
		} else if parts.len == 2 {
			module := py_item(s.context.namespace, parts[0])
			if module == unsafe { nil } { return module }
			kind = py_attr(module, parts[1])
			drop(module)
		} else {
			kind = py_attr(s.context.builtins, parts[0])
		}
		if kind == unsafe { nil } { return kind }
		matched := C.PyObject_IsInstance(cause, kind)
		drop(kind)
		if matched < 0 { return unsafe { nil } }
		result[row[0]] = ah.Value(matched != 0)
	}
	return to_python(ah.Value(result))
}

fn (mut s PackageSession) exit_native(id string, details voidptr) voidptr {
	none_value := py_none()
	exceptional := C.PyTuple_GetItem(details, 0) != none_value
	drop(none_value)
	mut record := null()
	if exceptional {
		cause := C.PyTuple_GetItem(details, 1)
		mut index := -1
		for i, error in s.context.errors {
			if error.value == cause {
				index = i
				break
			}
		}
		if index < 0 {
			s.context.errors << Exception{ kind: own(C.PyTuple_GetItem(details, 0)), value: own(cause), live: true }
			C.PyList_Append(s.errors_py, cause)
			index = s.context.errors.len - 1
		}
		record = ah.Value({
			'binding_error': ah.Value(index)
		})
	}
	return to_python(s.context.primitive('exit', {
		'owner': ah.Value(id)
		'error': record
	}))
}
