// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module pysmoke

import cpythonapi as py

type ModelDestructor = fn (py.Ref)
type ModelCallback = fn (py.Ref, py.Ref) py.Ref

struct Model {
mut:
	refs       int = 1
	kind       string
	text       string
	number     i64
	children   []py.Ref
	context    voidptr
	destructor fn (py.Ref) = unsafe { nil }
	method     &py.Method  = unsafe { nil }
}

__global (
	model_live          int
	model_none          py.Ref
	model_error         string
	model_fail_tuple    bool
	model_fail_append   bool
	model_fail_capsule  bool
	model_fail_function bool
	model_events        []string
)

fn object(kind string) py.Ref {
	model_live++
	return py.Ref(&Model{ kind: kind })
}

fn model_inc(reference py.Ref) {
	mut value := unsafe { &Model(reference) }
	assert value.refs > 0
	value.refs++
}

fn model_dec(reference py.Ref) {
	mut value := unsafe { &Model(reference) }
	assert value.refs > 0
	value.refs--
	if value.refs > 0 { return }
	for child in value.children { if child != unsafe { nil } { model_dec(child) } }
	if value.destructor != unsafe { nil } { value.destructor(reference) }
	model_live--
	unsafe { free(value) }
}

fn model_int(number i64) py.Ref {
	reference := object('integer')
	mut value := unsafe { &Model(reference) }
	value.number = number
	return reference
}

fn model_read_int(reference py.Ref) i64 { return unsafe { &Model(reference) }.number }

fn model_text(data &char, length isize) py.Ref {
	reference := object('unicode')
	mut value := unsafe { &Model(reference) }
	value.text = if length == 0 { '' } else { unsafe { tos(&u8(data), int(length)).clone() } }
	return reference
}

fn model_unicode(reference py.Ref, length &isize) &char {
	value := unsafe { &Model(reference) }
	unsafe { *length = value.text.len }
	return value.text.str
}

fn model_tuple(length isize) py.Ref {
	reference := object('tuple')
	mut value := unsafe { &Model(reference) }
	value.children = []py.Ref{len: int(length), init: py.Ref(unsafe { nil })}
	return reference
}

fn model_put_tuple(reference py.Ref, index isize, child py.Ref) i32 {
	mut value := unsafe { &Model(reference) }
	if model_fail_tuple {
		model_fail_tuple = false
		model_dec(child)
		model_error = 'SDKFailure'
		return -1
	}
	assert value.refs == 1 && index >= 0 && index < value.children.len
	value.children[int(index)] = child // consumes the separately incremented reference
	return 0
}

fn model_item(reference py.Ref, index isize) py.Ref {
	value := unsafe { &Model(reference) }
	child := value.children[int(index)]
	model_inc(child)
	return child
}

fn model_list(_ isize) py.Ref { return object('list') }

fn model_append(reference py.Ref, child py.Ref) i32 {
	if model_fail_append {
		model_fail_append = false
		model_error = 'SDKFailure'
		return -1
	}
	mut value := unsafe { &Model(reference) }
	model_inc(child)
	value.children << child
	return 0
}

fn model_dict() py.Ref { return object('dict') }

fn model_dict_put(reference py.Ref, _ &char, child py.Ref) i32 {
	return model_append(reference, child)
}

fn model_size(reference py.Ref) isize { return unsafe { &Model(reference) }.children.len }

fn model_truth(reference py.Ref) i32 {
	value := unsafe { &Model(reference) }
	if value.kind == 'bad' {
		model_error = 'SDKFailure'
		return -1
	}
	return if value.number == 0 { 0 } else { 1 }
}

fn model_compare(left py.Ref, right py.Ref, operation i32) i32 {
	assert operation == 2
	if unsafe { &Model(left) }.kind == 'bad' {
		model_error = 'SDKFailure'
		return -1
	}
	return if model_read_int(left) == model_read_int(right) { 1 } else { 0 }
}

fn model_occurred() py.Ref {
	return if model_error == '' { py.Ref(unsafe { nil }) } else { model_none }
}

fn model_fetch(kind &py.Ref, value &py.Ref, trace &py.Ref) {
	mut error_type := py.Ref(unsafe { nil })
	if model_error != '' {
		error_type = object('error')
		mut state := unsafe { &Model(error_type) }
		state.text = model_error
	}
	model_error = ''
	unsafe {
		*kind = error_type
		*value = nil
		*trace = nil
	}
}

fn model_set_error(_ py.Ref, _ &char) { model_error = 'RuntimeError' }

fn model_attr(reference py.Ref, name &char) py.Ref {
	owner := unsafe { &Model(reference) }
	if owner.kind == 'error' {
		assert unsafe { name.vstring() } == '__name__'
		return model_text(owner.text.str, owner.text.len)
	}
	result := object('method')
	mut value := unsafe { &Model(result) }
	value.text = unsafe { name.vstring().clone() }
	model_inc(reference)
	value.children << reference
	return result
}

fn model_call(reference py.Ref, args py.Ref, keywords py.Ref) py.Ref {
	value := unsafe { &Model(reference) }
	arguments := unsafe { &Model(args) }
	assert arguments.kind == 'tuple'
	if keywords != unsafe { nil } {
		assert unsafe { &Model(keywords) }.kind == 'dict'
	}
	if value.kind == 'function' {
		assert value.method.flags == 1 && value.children.len == 1
		method := unsafe { ModelCallback(value.method.function) }
		return method(value.children[0], args)
	}
	if value.kind == 'target' { return model_int(arguments.children.len) }
	assert value.kind == 'method'
	model_events << value.text
	if value.text == 'wait' {
		assert arguments.children.len == 1 && model_read_int(arguments.children[0]) == 5
	}
	model_inc(model_none)
	return model_none
}

fn model_capsule(context voidptr, _ &char, destructor voidptr) py.Ref {
	if model_fail_capsule {
		model_fail_capsule = false
		model_error = 'SDKFailure'
		return py.Ref(unsafe { nil })
	}
	result := object('capsule')
	mut value := unsafe { &Model(result) }
	value.context = context
	value.destructor = unsafe { ModelDestructor(destructor) }
	return result
}

fn model_pointer(reference py.Ref, _ &char) voidptr { return unsafe { &Model(reference) }.context }

fn model_function(method &py.Method, capsule py.Ref, _ py.Ref) py.Ref {
	if model_fail_function {
		model_fail_function = false
		model_error = 'SDKFailure'
		return py.Ref(unsafe { nil })
	}
	result := object('function')
	mut value := unsafe { &Model(result) }
	value.method = unsafe { method }
	model_inc(capsule)
	value.children << capsule
	return result
}

fn api_model() py.Api {
	assert model_live == 0 && model_error == ''
	model_none = object('none')
	model_events = []string{}
	return py.Api{
		inc:             model_inc
		dec:             model_dec
		integer:         model_int
		boolean:         model_int
		as_integer:      model_read_int
		unicode:         model_text
		unicode_data:    model_unicode
		tuple:           model_tuple
		tuple_put:       model_put_tuple
		item:            model_item
		list:            model_list
		append:          model_append
		dict:            model_dict
		dict_put:        model_dict_put
		size:            model_size
		truth:           model_truth
		compare:         model_compare
		error_occurred:  model_occurred
		error_fetch:     model_fetch
		error_string:    model_set_error
		attribute:       model_attr
		call:            model_call
		capsule_new:     model_capsule
		capsule_pointer: model_pointer
		function_new:    model_function
		none:            model_none
		runtime_error:   model_none
	}
}

fn release_model() {
	model_dec(model_none)
	assert model_live == 0 && model_error == ''
}

fn test_arena_new_borrowed_stolen_error_and_retired_reference_contracts() {
	api := api_model()
	mut a := py.Arena{ api: &api }
	for number in [i64(-1), -9223372036854775807, 9223372036854775807] {
		value := a.int(number) or { panic(err) }
		assert a.integer(value) or { panic(err) } == number
		pair := a.tuple([value, value]) or { panic(err) }
		assert unsafe { &Model(value) }.refs == 3
		assert a.item(pair, 0) or { panic(err) } == value
		assert a.borrow(value) or { panic(err) } == value
		assert unsafe { &Model(value) }.refs == 5
		model_fail_tuple = true
		a.tuple([value]) or { assert err.msg() == 'SDKFailure' }
		assert unsafe { &Model(value) }.refs == 5 && model_error == ''
		items := a.list([value]) or { panic(err) }
		assert a.length(items) or { panic(err) } == 1
	}
	text := a.text('é\x00漢字😀') or { panic(err) }
	assert a.string(text) or { panic(err) } == 'é\x00漢字😀'
	assert a.truth(a.boolean(true) or { panic(err) }) or { panic(err) }
	assert !(a.truth(a.boolean(false) or { panic(err) }) or { panic(err) })
	bad := a.take(object('bad')) or { panic(err) }
	a.truth(bad) or { assert err.msg() == 'SDKFailure' }
	a.equal(bad, text) or { assert err.msg() == 'SDKFailure' }
	assert model_error == ''
	target := a.take(object('target')) or { panic(err) }
	result := a.call(target, [text], {
		'retained': text
	}) or { panic(err) }
	assert a.integer(result) or { panic(err) } == 1
	a.close()
	a.close()
	assert model_live == 1
	a.take(model_int(5)) or { assert err.msg() == 'CPython arena is retired' }
	assert model_live == 1
	a.borrow(model_none) or { assert err.msg() == 'invalid CPython borrowed reference' }
	a.integer(text) or { assert err.msg() == 'CPython arena is retired' }
	a.string(text) or { assert err.msg() == 'CPython arena is retired' }
	a.text('no SDK call') or { assert err.msg() == 'CPython arena is retired' }
	assert unsafe { &Model(model_none) }.refs == 1
	release_model()
}

fn test_capsule_owns_definitions_and_sdk_objects_beyond_arena_retirement() {
	mut api := api_model()
	callback_api = &api
	mut a := py.Arena{ api: &api }
	seen := a.list([]) or { panic(err) }
	mutex := a.take(object('lock')) or { panic(err) }
	function := callback(mut a, seen, mutex, c'worker', voidptr(worker_callback)) or { panic(err) }
	model_inc(function) // SDK retains this callable after its producer closes.
	a.close()
	assert unsafe { &Model(seen) }.refs == 1 && unsafe { &Model(mutex) }.refs == 1
	mut calls := py.Arena{ api: &api }
	for number in 0 .. 8 {
		calls.call(function, [calls.int(number) or { panic(err) }], {}) or { panic(err) }
	}
	assert unsafe { &Model(seen) }.children.len == 8
	for index, value in unsafe { &Model(seen) }.children {
		assert model_read_int(value) == index
	}
	assert model_events == ['acquire', 'release'].repeat(8)
	model_fail_append = true
	calls.call(function, [calls.int(9) or { panic(err) }], {}) or { assert err.msg() == 'RuntimeError' }
	assert model_error == '' && model_events.last() == 'release'
	calls.close()
	model_dec(function)
	callback_api = unsafe { nil }
	release_model()
}

fn test_waiter_deadline_and_capsule_function_creation_failures_release_owners() {
	mut api := api_model()
	callback_api = &api
	mut a := py.Arena{ api: &api }
	seen := a.list([]) or { panic(err) }
	wake := a.take(object('event')) or { panic(err) }
	model_fail_capsule = true
	callback(mut a, seen, wake, c'waiter', voidptr(waiter_callback)) or { assert err.msg() == 'SDKFailure' }
	assert unsafe { &Model(seen) }.refs == 1 && unsafe { &Model(wake) }.refs == 1
	model_fail_function = true
	callback(mut a, seen, wake, c'waiter', voidptr(waiter_callback)) or { assert err.msg() == 'SDKFailure' }
	function := callback(mut a, seen, wake, c'waiter', voidptr(waiter_callback)) or { panic(err) }
	a.call(function, [], {}) or { panic(err) }
	assert model_events == ['wait']
	assert unsafe { &Model(seen) }.children.len == 1
	child := unsafe { &Model(seen) }.children[0]
	assert unsafe { &Model(child) }.text == 'woken'
	assert sizeof(py.Method) == 32
	definition := py.Method{ name: c'ABI', function: voidptr(worker_callback) }
	assert sizeof(definition.flags) == 4
	assert unsafe { usize(&definition.flags) - usize(&definition) } == 16
	assert unsafe { usize(&definition.doc) - usize(&definition) } == 24
	a.close()
	callback_api = unsafe { nil }
	release_model()
}
