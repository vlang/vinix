// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

import androidhost as ah
import json2

#include <Python.h>
#include <pythread.h>

@[typedef]
pub struct C.PyTypeObject {
	tp_mro       voidptr
	tp_dict      voidptr
	tp_descr_get fn (voidptr, voidptr, voidptr) voidptr
}

fn C.Py_TYPE(voidptr) &C.PyTypeObject

fn C.Py_IncRef(voidptr)
fn C.Py_DecRef(voidptr)
fn C.PyImport_ImportModule(&char) voidptr
fn C.PyModule_GetDict(voidptr) voidptr
fn C.PyObject_Call(voidptr, voidptr, voidptr) voidptr
fn C.PyObject_GetAttrString(voidptr, &char) voidptr
fn C.PyObject_SetAttrString(voidptr, &char, voidptr) i32
fn C.PyObject_Str(voidptr) voidptr
fn C.PyObject_IsTrue(voidptr) i32
fn C.PyObject_IsInstance(voidptr, voidptr) i32
fn C.PyObject_GetIter(voidptr) voidptr
fn C.PyIter_Next(voidptr) voidptr
fn C.PyCallable_Check(voidptr) i32
fn C.PyDict_New() voidptr
fn C.PyDict_GetItemString(voidptr, &char) voidptr
fn C.PyDict_GetItem(voidptr, voidptr) voidptr
fn C.PyDict_SetItemString(voidptr, &char, voidptr) i32
fn C.PyDict_Next(voidptr, &isize, &voidptr, &voidptr) i32
fn C.PyTuple_New(isize) voidptr
fn C.PyTuple_SetItem(voidptr, isize, voidptr) i32
fn C.PyTuple_GetItem(voidptr, isize) voidptr
fn C.PyTuple_Size(voidptr) isize
fn C.PyList_New(isize) voidptr
fn C.PyList_SetItem(voidptr, isize, voidptr) i32
fn C.PyList_GetItem(voidptr, isize) voidptr
fn C.PyList_Size(voidptr) isize
fn C.PyBool_FromLong(isize) voidptr
fn C.PyFloat_FromDouble(f64) voidptr
fn C.PyFloat_FromString(voidptr) voidptr
fn C.PyFloat_AsDouble(voidptr) f64
fn C.PyLong_FromLongLong(i64) voidptr
fn C.PyLong_FromString(&char, &voidptr, i32) voidptr
fn C.PyLong_AsLongLongAndOverflow(voidptr, &i32) i64
fn C.PyLong_Check(voidptr) i32
fn C.PyFloat_Check(voidptr) i32
fn C.PyBool_Check(voidptr) i32
fn C.PyUnicode_Check(voidptr) i32
fn C.PyList_Check(voidptr) i32
fn C.PyTuple_Check(voidptr) i32
fn C.PyDict_Check(voidptr) i32
fn C.PyUnicode_DecodeUTF8(&char, isize, &char) voidptr
fn C.PyUnicode_AsEncodedString(voidptr, &char, &char) voidptr
fn C.PyBytes_FromStringAndSize(&char, isize) voidptr
fn C.PyBytes_AsString(voidptr) &char
fn C.PyBytes_Size(voidptr) isize
fn C.Py_BuildValue(&char) voidptr
fn C.PyErr_Occurred() voidptr
fn C.PyErr_Fetch(&voidptr, &voidptr, &voidptr)
fn C.PyErr_Restore(voidptr, voidptr, voidptr)
fn C.PyErr_NormalizeException(&voidptr, &voidptr, &voidptr)
fn C.PyErr_GetExcInfo(&voidptr, &voidptr, &voidptr)
fn C.PyErr_SetExcInfo(voidptr, voidptr, voidptr)
fn C.PyErr_SetObject(voidptr, voidptr)
fn C.PyErr_Clear()
fn C.PyErr_CheckSignals() i32
fn C.PyException_SetTraceback(voidptr, voidptr) i32
fn C.PyException_GetTraceback(voidptr) voidptr
fn C.PyErr_GivenExceptionMatches(voidptr, voidptr) i32
fn C.PyExceptionClass_Check(voidptr) i32
fn C.PyThread_tss_alloc() voidptr
fn C.PyThread_tss_create(voidptr) i32
fn C.PyThread_tss_get(voidptr) voidptr
fn C.PyThread_tss_set(voidptr, voidptr) i32

__global cpython_context_tss = voidptr(0)

@[c_extern]
__global C.PyExc_NameError voidptr

@[c_extern]
__global C.PyExc_AttributeError voidptr

@[c_extern]
__global C.PyExc_TypeError voidptr

fn own(p voidptr) voidptr {
	unsafe { C.Py_IncRef(p) }
	return p
}

fn drop(p voidptr) {
	unsafe { C.Py_DecRef(p) }
}

fn null() ah.Value { return ah.Value(json2.Null{}) }

fn py_none() voidptr { return C.Py_BuildValue(c'') }

fn py_string(s string) voidptr {
	return unsafe { C.PyUnicode_DecodeUTF8(s.str, s.len, c'surrogatepass') }
}

fn string_value(p voidptr) string {
	b := C.PyUnicode_AsEncodedString(p, c'utf-8', c'surrogatepass')
	if b == unsafe { nil } { return '' }
	defer { drop(b) }
	return unsafe { C.PyBytes_AsString(b).vstring_with_len(int(C.PyBytes_Size(b))).clone() }
}

fn to_python(v ah.Value) voidptr {
	return match v {
		string { py_string(v) }
		bool { C.PyBool_FromLong(if v { 1 } else { 0 }) }
		int { C.PyLong_FromLongLong(i64(v)) }
		i64 { C.PyLong_FromLongLong(v) }
		u64 {
			text := v.str()
			unsafe { C.PyLong_FromString(text.str, nil, 10) }
		}
		ah.Number {
			if v.text.contains('.') || v.text.contains('e') || v.text.contains('E') {
				text := py_string(v.text)
				value := C.PyFloat_FromString(text)
				drop(text)
				value
			} else {
				unsafe { C.PyLong_FromString(v.text.str, nil, 10) }
			}
		}
		[]ah.Value {
			p := C.PyList_New(v.len)
			for i, item in v { C.PyList_SetItem(p, i, to_python(item)) }
			p
		}
		map[string]ah.Value {
			p := C.PyDict_New()
			for name, item in v {
				q := to_python(item)
				unsafe { C.PyDict_SetItemString(p, name.str, q) }
				drop(q)
			}
			p
		}
		else { py_none() }
	}
}

fn from_python(p voidptr) ah.Value {
	if p == unsafe { nil } { return null() }
	if C.PyBool_Check(p) != 0 { return ah.Value(C.PyObject_IsTrue(p) != 0) }
	if C.PyLong_Check(p) != 0 {
		mut overflow := i32(0)
		number := C.PyLong_AsLongLongAndOverflow(p, &overflow)
		if overflow == 0 { return ah.Value(number) }
		text := C.PyObject_Str(p)
		value := string_value(text)
		drop(text)
		return ah.Value(ah.Number{value})
	}
	if C.PyFloat_Check(p) != 0 { return ah.Value(ah.Number{C.PyFloat_AsDouble(p).str()}) }
	if C.PyUnicode_Check(p) != 0 { return ah.Value(string_value(p)) }
	if C.PyList_Check(p) != 0 || C.PyTuple_Check(p) != 0 {
		tuple := C.PyTuple_Check(p) != 0
		count := if tuple { C.PyTuple_Size(p) } else { C.PyList_Size(p) }
		mut result := []ah.Value{cap: int(count)}
		for i in 0 .. int(count) {
			result << from_python(if tuple {
				C.PyTuple_GetItem(p, i)
			} else {
				C.PyList_GetItem(p, i)
			})
		}
		return ah.Value(result)
	}
	if C.PyDict_Check(p) != 0 {
		mut position := isize(0)
		mut name := voidptr(0)
		mut value := voidptr(0)
		mut result := map[string]ah.Value{}
		for C.PyDict_Next(p, &position, &name, &value) != 0 {
			result[string_value(name)] = from_python(value)
		}
		return ah.Value(result)
	}
	return null()
}

struct Exception {
	kind      voidptr
	value     voidptr
	traceback voidptr
	live      bool
}

fn caught() Exception {
	mut kind := voidptr(0)
	mut value := voidptr(0)
	mut traceback := voidptr(0)
	C.PyErr_Fetch(&kind, &value, &traceback)
	C.PyErr_NormalizeException(&kind, &value, &traceback)
	if traceback != unsafe { nil } { C.PyException_SetTraceback(value, traceback) }
	drop(traceback)
	return Exception{ kind: kind, value: value, live: true }
}

fn handled() Exception {
	mut kind := voidptr(0)
	mut value := voidptr(0)
	mut traceback := voidptr(0)
	C.PyErr_GetExcInfo(&kind, &value, &traceback)
	return Exception{ kind: kind, value: value, traceback: traceback }
}

fn (e Exception) tb() voidptr {
	return if e.live { C.PyException_GetTraceback(e.value) } else { own(e.traceback) }
}

fn (e Exception) activate() { C.PyErr_SetExcInfo(own(e.kind), own(e.value), e.tb()) }

fn (e Exception) discard() {
	drop(e.kind)
	drop(e.value)
	drop(e.traceback)
}

fn (e Exception) restore() { C.PyErr_Restore(own(e.kind), own(e.value), e.tb()) }

pub struct Failure {
pub:
	value map[string]ah.Value
}

pub fn (e Failure) msg() string {
	context := current()
	index := int(ah.field(e.value, 'binding_error') as int)
	error := context.errors[index]
	before := handled()
	error.activate()
	message := C.PyObject_Str(error.value)
	text := if message == unsafe { nil } { '' } else { string_value(message) }
	drop(message)
	before.activate()
	before.discard()
	return text
}

pub fn (e Failure) code() int { return 0 }

struct Manager {
	id      string
	entered string
mut:
	active      bool = true
	exit_target voidptr
}

pub struct Context {
	namespace voidptr
	syntax    voidptr
	builtins  voidptr
	operator  voidptr
	incoming  Exception
	previous  voidptr
mut:
	objects  map[string]voidptr
	errors   []Exception
	managers []Manager
	next_id  int
	active   int = -1
}

pub fn begin(namespace voidptr, syntax voidptr) &Context {
	if cpython_context_tss == unsafe { nil } {
		cpython_context_tss = C.PyThread_tss_alloc()
		C.PyThread_tss_create(cpython_context_tss)
	}
	context := &Context{ namespace: own(namespace), syntax: own(syntax), builtins: C.PyImport_ImportModule(c'builtins'), operator: C.PyImport_ImportModule(c'operator'), incoming: handled(), previous: C.PyThread_tss_get(cpython_context_tss) }
	C.PyThread_tss_set(cpython_context_tss, context)
	return context
}

fn current() &Context { return unsafe { &Context(C.PyThread_tss_get(cpython_context_tss)) } }

pub fn (mut c Context) retain(p voidptr) string {
	id := c.next_id.str()
	c.next_id++
	c.objects[id] = p
	return id
}

fn (c &Context) borrowed(id string) voidptr { return c.objects[id] or { unsafe { nil } } }

fn (mut c Context) release(id string) {
	if id !in c.objects { return }
	for manager in c.managers {
		if manager.active && manager.entered == id { return }
	}
	p := c.objects[id]
	c.objects.delete(id)
	drop(p)
}

fn (c &Context) resolve(name string) voidptr {
	components := name.split('.')
	mut result := if components[0] == 'builtins' {
		own(c.builtins)
	} else if components[0] == 'operator' {
		own(c.operator)
	} else {
		value := unsafe { C.PyDict_GetItemString(c.namespace, components[0].str) }
		if value != unsafe { nil } {
			own(value)
		} else {
			fallback := unsafe { C.PyDict_GetItemString(C.PyModule_GetDict(c.builtins), components[0].str) }
			if fallback == unsafe { nil } {
				message := py_string("name '" + components[0] + "' is not defined")
				C.PyErr_SetObject(unsafe { voidptr(C.PyExc_NameError) }, message)
				drop(message)
				unsafe { nil }
			} else {
				own(fallback)
			}
		}
	}
	if result == unsafe { nil } { return result }
	for part in components[1..] {
		next := unsafe { C.PyObject_GetAttrString(result, part.str) }
		drop(result)
		result = next
		if result == unsafe { nil } { break }
	}
	return result
}

fn (c &Context) operand(value ah.Value) voidptr {
	parts := value.items()
	if parts[0].text() == 'owner' { return own(c.borrowed(parts[1].text())) }
	if parts[0].text() == 'bytes' {
		factory := C.PyObject_GetAttrString(c.builtins, c'bytes')
		parser := C.PyObject_GetAttrString(factory, c'fromhex')
		drop(factory)
		args := C.PyTuple_New(1)
		C.PyTuple_SetItem(args, 0, py_string(parts[1].text()))
		result := C.PyObject_Call(parser, args, unsafe { nil })
		drop(args)
		drop(parser)
		return result
	}
	return to_python(parts[1])
}

fn (c &Context) arguments(values []ah.Value) voidptr {
	args := C.PyTuple_New(values.len)
	for i, value in values {
		item := c.operand(value)
		if item == unsafe { nil } {
			drop(args)
			return unsafe { nil }
		}
		C.PyTuple_SetItem(args, i, item)
	}
	return args
}

fn (c &Context) keywords(values map[string]ah.Value) voidptr {
	kwargs := C.PyDict_New()
	for name, value in values {
		item := c.operand(value)
		if item == unsafe { nil } {
			drop(kwargs)
			return unsafe { nil }
		}
		unsafe { C.PyDict_SetItemString(kwargs, name.str, item) }
		drop(item)
	}
	return kwargs
}

fn (mut c Context) failure(error Exception) Failure {
	index := c.errors.len
	c.errors << error
	record := {
		'binding_error': ah.Value(index)
	}
	return Failure{record}
}

fn (mut c Context) result(p voidptr, data bool) ah.Value {
	if data {
		defer { drop(p) }
		return from_python(p)
	}
	return ah.Value(c.retain(p))
}

fn (mut c Context) call(row map[string]ah.Value) ah.Value {
	target := if 'target' in row {
		own(c.borrowed(row['target'].text()))
	} else if 'owner' in row {
		name := row['name'].text()
		unsafe { C.PyObject_GetAttrString(c.borrowed(row['owner'].text()), name.str) }
	} else {
		c.resolve(row['name'].text())
	}
	if target == unsafe { nil } { return null() }
	defer { drop(target) }
	if C.PyCallable_Check(target) == 0 && !('call' in row && row['call'] as bool) {
		return c.result(own(target), 'data' in row && row['data'] as bool)
	}
	args := c.arguments(if 'args' in row { row['args'].items() } else { []ah.Value{} })
	if args == unsafe { nil } { return null() }
	defer { drop(args) }
	kwargs := c.keywords(if 'kwargs' in row {
		row['kwargs'].object()
	} else {
		map[string]ah.Value{}
	})
	if kwargs == unsafe { nil } { return null() }
	defer { drop(kwargs) }
	result := if 'kwargs_owner' in row {
		helper := unsafe { C.PyDict_GetItemString(c.syntax, c'double_kwargs') }
		joined := C.PyTuple_New(4)
		C.PyTuple_SetItem(joined, 0, own(target))
		C.PyTuple_SetItem(joined, 1, own(args))
		C.PyTuple_SetItem(joined, 2, own(kwargs))
		C.PyTuple_SetItem(joined, 3, own(c.borrowed(row['kwargs_owner'].text())))
		value := C.PyObject_Call(helper, joined, unsafe { nil })
		drop(joined)
		value
	} else {
		C.PyObject_Call(target, args, kwargs)
	}
	if result == unsafe { nil } { return null() }
	return c.result(result, 'data' in row && row['data'] as bool)
}

pub fn callback(name string, row map[string]ah.Value) !ah.Value {
	mut c := current()
	if name == 'active_error' {
		value := ah.field(row, 'error')
		c.active = if value is json2.Null {
			-1
		} else {
			int(ah.field(value.object(), 'binding_error') as int)
		}
		return null()
	}
	before := handled()
	if c.active < 0 { c.incoming.activate() } else { c.errors[c.active].activate() }
	check := name !in ['release', 'release_since', 'exit', 'close']
	result := if check && C.PyErr_CheckSignals() != 0 { null() } else { c.primitive(name, row) }
	failure := if C.PyErr_Occurred() != unsafe { nil } { caught() } else { Exception{} }
	if failure.kind != unsafe { nil } {
		failure.activate()
		record := c.failure(failure)
		before.activate()
		before.discard()
		return record
	}
	before.activate()
	before.discard()
	return result
}

fn (mut c Context) primitive(name string, row map[string]ah.Value) ah.Value {
	match name {
		'checkpoint' { return ah.Value(c.next_id) }
		'release' {
			for id in row['ids'].items() { c.release(id.text()) }
			return null()
		}
		'release_since' {
			start := int(row['checkpoint'] as int)
			keep := if 'keep' in row { row['keep'].items().map(it.text()) } else { []string{} }
			for id in c.objects.keys() { if id.int() >= start && id !in keep { c.release(id) } }
			return null()
		}
		'resolve' { return c.result(c.resolve(row['name'].text()), false) }
		'literal' { return c.result(c.operand(row['value']), false) }
		'attribute' {
			name_ := row['name'].text()
			return c.result(unsafe { C.PyObject_GetAttrString(c.borrowed(row['owner'].text()), name_.str) }, false)
		}
		'set_attribute' {
			value := c.operand(row['value'])
			name_ := row['name'].text()
			unsafe { C.PyObject_SetAttrString(c.borrowed(row['owner'].text()), name_.str, value) }
			drop(value)
			return null()
		}
		'function' { return c.call(row) }
		'collection' {
			values := row['values'].items()
			list := C.PyList_New(values.len)
			for i, id in values { C.PyList_SetItem(list, i, own(c.borrowed(id.text()))) }
			kind := row['kind'].text()
			if kind == 'list' { return c.result(list, false) }
			target := c.resolve('builtins.' + kind)
			args := C.PyTuple_New(1)
			C.PyTuple_SetItem(args, 0, list)
			result := C.PyObject_Call(target, args, unsafe { nil })
			drop(args)
			drop(target)
			return c.result(result, false)
		}
		'next' {
			item := C.PyIter_Next(c.borrowed(row['owner'].text()))
			if item == unsafe { nil } {
				return ah.Value({
					'done': ah.Value(true)
				})
			}
			return ah.Value({
				'done':  ah.Value(false)
				'value': ah.Value(c.retain(item))
			})
		}
		'unpack_pair' {
			helper := unsafe { C.PyDict_GetItemString(c.syntax, c'pair') }
			args := C.PyTuple_New(1)
			C.PyTuple_SetItem(args, 0, own(c.borrowed(row['owner'].text())))
			pair := C.PyObject_Call(helper, args, unsafe { nil })
			drop(args)
			if pair == unsafe { nil } { return null() }
			first := c.retain(own(C.PyTuple_GetItem(pair, 0)))
			second := c.retain(own(C.PyTuple_GetItem(pair, 1)))
			drop(pair)
			return ah.Value([ah.Value(first), ah.Value(second)])
		}
		'enter' {
			id := row['owner'].text()
			target := c.special(c.borrowed(id), '__enter__')
			if target == unsafe { nil } { return null() }
			exit_target := c.special(c.borrowed(id), '__exit__')
			if exit_target == unsafe { nil } {
				drop(target)
				return null()
			}
			consume := ah.field(row, 'consume')
			if consume is bool && consume { c.release(id) }
			args := C.PyTuple_New(0)
			value := C.PyObject_Call(target, args, unsafe { nil })
			drop(args)
			drop(target)
			if value == unsafe { nil } {
				drop(exit_target)
				return null()
			}
			entered := c.retain(value)
			c.managers << Manager{ id: id, entered: entered, exit_target: exit_target }
			return ah.Value(entered)
		}
		'exit' {
			id := row['owner'].text()
			for i, manager in c.managers {
				if manager.active && manager.id == id {
					c.managers[i].active = false
					c.managers[i].exit_target = unsafe { nil }
					return c.exit_manager(manager, ah.field(row, 'error'))
				}
			}
			return ah.Value(false)
		}
		'error_object' {
			return c.result(own(c.errors[int(ah.field(row['error'].object(), 'binding_error') as int)].value), false)
		}
		'exception_matches' {
			error := c.errors[int(ah.field(row['error'].object(), 'binding_error') as int)]
			class := c.borrowed(row['class'].text())
			before := handled()
			error.activate()
			mut valid := true
			if C.PyTuple_Check(class) != 0 {
				for i in 0 .. int(C.PyTuple_Size(class)) {
					if C.PyExceptionClass_Check(C.PyTuple_GetItem(class, i)) == 0 {
						valid = false
						break
					}
				}
			} else {
				valid = C.PyExceptionClass_Check(class) != 0
			}
			if !valid {
				text := py_string('catching classes that do not inherit from BaseException is not allowed')
				C.PyErr_SetObject(unsafe { voidptr(C.PyExc_TypeError) }, text)
				drop(text)
				before.activate()
				before.discard()
				return null()
			}
			matches := C.PyErr_GivenExceptionMatches(error.kind, class) != 0
			before.activate()
			before.discard()
			return ah.Value(matches)
		}
		'raise' {
			kind := c.resolve(row['kind'].text())
			args := if 'args' in row {
				c.arguments(row['args'].items())
			} else {
				values := C.PyTuple_New(1)
				C.PyTuple_SetItem(values, 0, py_string(row['message'].text()))
				values
			}
			error := C.PyObject_Call(kind, args, unsafe { nil })
			drop(args)
			if error != unsafe { nil } {
				C.PyErr_SetObject(kind, error)
				drop(error)
			}
			drop(kind)
			return null()
		}
		else { panic('unsupported prototype primitive: ' + name) }
	}
}

// Python with-statements look up special methods through the real type MRO,
// bypassing instance hooks, and cache the exit callable before entering.
fn (c &Context) special(instance voidptr, name string) voidptr {
	owner := C.Py_TYPE(instance)
	key := py_string(name)
	defer { drop(key) }
	mro := unsafe { owner.tp_mro }
	for i in 0 .. int(C.PyTuple_Size(mro)) {
		base := unsafe { &C.PyTypeObject(C.PyTuple_GetItem(mro, i)) }
		descriptor := C.PyDict_GetItem(unsafe { base.tp_dict }, key)
		if descriptor == unsafe { nil } { continue }
		own(descriptor)
		defer { drop(descriptor) }
		descriptor_type := C.Py_TYPE(descriptor)
		if unsafe { descriptor_type.tp_descr_get } == unsafe { nil } { return own(descriptor) }
		return unsafe { descriptor_type.tp_descr_get(descriptor, instance, owner) }
	}
	C.PyErr_SetObject(unsafe { voidptr(C.PyExc_AttributeError) }, key)
	return unsafe { nil }
}

fn (mut c Context) exit_manager(manager Manager, record ah.Value) ah.Value {
	target := manager.exit_target
	if target == unsafe { nil } { return null() }
	before := handled()
	exceptional := record !is json2.Null
	args := C.PyTuple_New(3)
	if exceptional {
		error := c.errors[int(ah.field(record.object(), 'binding_error') as int)]
		error.activate()
		C.PyTuple_SetItem(args, 0, own(error.kind))
		C.PyTuple_SetItem(args, 1, own(error.value))
		tb := error.tb()
		C.PyTuple_SetItem(args, 2, if tb == unsafe { nil } { py_none() } else { tb })
	} else {
		for i in 0 .. 3 { C.PyTuple_SetItem(args, i, py_none()) }
	}
	result := C.PyObject_Call(target, args, unsafe { nil })
	drop(args)
	if !exceptional { drop(target) }
	truth := if result == unsafe { nil } {
		false
	} else if exceptional {
		C.PyObject_IsTrue(result) != 0
	} else {
		false
	}
	drop(result)
	// Exceptional with cleanup restores the caller's handled state before
	// the cached exit callable leaves the value stack. Preserve a new pending
	// exception separately while that callable's destructor can run Python.
	mut kind := voidptr(0)
	mut value := voidptr(0)
	mut traceback := voidptr(0)
	C.PyErr_Fetch(&kind, &value, &traceback)
	before.activate()
	before.discard()
	if exceptional { drop(target) }
	C.PyErr_Restore(kind, value, traceback)
	return ah.Value(truth)
}

pub fn (mut c Context) finish(result voidptr, failed int) voidptr {
	mut failure := failed
	for i := c.managers.len - 1; i >= 0; i-- {
		manager := c.managers[i]
		if !manager.active { continue }
		c.managers[i].active = false
		c.managers[i].exit_target = unsafe { nil }
		record := if failure >= 0 {
			ah.Value({
				'binding_error': ah.Value(failure)
			})
		} else {
			null()
		}
		suppressed := c.exit_manager(manager, record) as bool
		if C.PyErr_Occurred() != unsafe { nil } {
			c.errors << caught()
			failure = c.errors.len - 1
		} else if suppressed {
			failure = -1
		}
	}
	pending := if failure >= 0 { c.errors[failure] } else { Exception{} }
	if failure >= 0 { drop(result) }
	c.incoming.activate()
	C.PyThread_tss_set(cpython_context_tss, c.previous)
	for id in c.objects.keys() { c.release(id) }
	drop(c.namespace)
	drop(c.syntax)
	drop(c.builtins)
	drop(c.operator)
	if failure >= 0 {
		own(pending.kind)
		own(pending.value)
	}
	for error in c.errors { error.discard() }
	c.incoming.discard()
	if failure >= 0 { C.PyErr_Restore(pending.kind, pending.value, pending.tb()) }
	return if failure >= 0 { unsafe { nil } } else { result }
}

pub fn get_result(id string) voidptr { return own(current().borrowed(id)) }

pub fn none_result() voidptr { return py_none() }

pub fn (mut c Context) native_error(message string) voidptr {
	if C.PyErr_Occurred() == unsafe { nil } {
		kind := c.resolve('builtins.RuntimeError')
		value := py_string(message)
		C.PyErr_SetObject(kind, value)
		drop(value)
		drop(kind)
	}
	c.errors << caught()
	return c.finish(unsafe { nil }, c.errors.len - 1)
}

pub fn pending_error() bool { return C.PyErr_Occurred() != unsafe { nil } }
