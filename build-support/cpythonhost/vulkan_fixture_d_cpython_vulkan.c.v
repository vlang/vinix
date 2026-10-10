// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

fn C.PyObject_SetAttr(voidptr, voidptr, voidptr) i32
fn C.PyDict_Copy(voidptr) voidptr

__global vulkan_fixture_completed = voidptr(0)
__global vulkan_fixture_return_member = voidptr(0)

fn fixture_pair(first string, second string, completed bool) voidptr {
	mut value := if completed { vulkan_fixture_completed } else { vulkan_fixture_return_member }
	if value != unsafe { nil } { return own(value) }
	a := vulkan_literal(first)
	if a == unsafe { nil } { return a }
	b := vulkan_literal(second)
	if b == unsafe { nil } { drop(a); return b }
	value = C.PyTuple_New(2)
	if value == unsafe { nil } { drop(b); drop(a); return value }
	C.PyTuple_SetItem(value, 0, a)
	C.PyTuple_SetItem(value, 1, b)
	if completed { vulkan_fixture_completed = own(value) } else { vulkan_fixture_return_member = own(value) }
	return value
}

fn fixture_set(value voidptr, name string, item voidptr) i32 {
	key := vulkan_literal(name)
	if key == unsafe { nil } { return -1 }
	status := C.PyObject_SetAttr(value, key, item)
	drop(key)
	return status
}

// The options expression has a fresh subscription at each conditional arm.
// Its temporary kind retires before truth is requested from the rich result.
fn fixture_kind(descriptor voidptr, name string) i32 {
	kind := vulkan_item(descriptor, 'kind')
	if kind == unsafe { nil } { return -1 }
	key := vulkan_literal(name)
	if key == unsafe { nil } { drop(kind); return -1 }
	compared := C.PyObject_RichCompare(kind, key, 2)
	drop(kind)
	drop(key)
	if compared == unsafe { nil } { return -1 }
	truth := C.PyObject_IsTrue(compared)
	drop(compared)
	return truth
}

fn fixture_options(descriptor voidptr, value voidptr) voidptr {
	mut key := 'new'
	wrap := fixture_kind(descriptor, 'wrap')
	if wrap < 0 { return unsafe { nil } }
	if wrap != 0 { key = 'wraps' } else {
		callback := fixture_kind(descriptor, 'callback')
		if callback < 0 { return unsafe { nil } }
		if callback != 0 { key = 'side_effect' } else {
			kind := vulkan_item(descriptor, 'kind')
			if kind == unsafe { nil } { return kind }
			pair := fixture_pair('return', 'member', false)
			if pair == unsafe { nil } { drop(kind); return pair }
			matched := C.PySequence_Contains(pair, kind)
			drop(kind)
			drop(pair)
			if matched < 0 { return unsafe { nil } }
			if matched != 0 { key = 'return_value' }
		}
	}
	return vulkan_dictionary(key, value)
}

fn (c &VulkanContext) fixture_enter(self voidptr, contexts voidptr) voidptr {
	manager := vulkan_attr(self, 'manager')
	if manager == unsafe { nil } { return manager }
	entered := vulkan_temporary_method(manager, '__enter__', [])
	if entered == unsafe { nil } { return entered }
	defer { c.pin(['entered'], [entered]); drop(entered) }
	active := C.PyBool_FromLong(1)
	if active == unsafe { nil } { return active }
	status := fixture_set(self, 'active', active)
	drop(active)
	if status != 0 { return unsafe { nil } }
	pushed := vulkan_method(contexts, 'push', [self])
	if pushed == unsafe { nil } { return pushed }
	drop(pushed)
	return own(entered)
}

fn fixture_exit(self voidptr, error_ voidptr) voidptr {
	active := vulkan_attr(self, 'active')
	if active == unsafe { nil } { return active }
	truth := C.PyObject_IsTrue(active)
	drop(active)
	if truth < 0 { return unsafe { nil } }
	if truth == 0 { return C.PyBool_FromLong(0) }
	false_ := C.PyBool_FromLong(0)
	if false_ == unsafe { nil } { return false_ }
	status := fixture_set(self, 'active', false_)
	drop(false_)
	if status != 0 { return unsafe { nil } }
	manager := vulkan_attr(self, 'manager')
	if manager == unsafe { nil } { return manager }
	target := vulkan_attr(manager, '__exit__')
	drop(manager)
	if target == unsafe { nil } { return target }
	result := C.PyObject_Call(target, error_, unsafe { nil })
	drop(target)
	return result
}

fn vulkan_fixture(arguments voidptr, pins voidptr) voidptr {
	c := VulkanContext{sdk: C.PyTuple_GetItem(arguments, 0), builtins: C.PyEval_GetBuiltins(), pins: pins}
	op := string_value(C.PyTuple_GetItem(arguments, 1))
	values := C.PyTuple_GetItem(arguments, 2)
	first := C.PyTuple_GetItem(values, 0)
	if op == 'options' { return fixture_options(first, C.PyTuple_GetItem(values, 1)) }
	if op == 'init' {
		if fixture_set(first, 'manager', C.PyTuple_GetItem(values, 1)) != 0 { return unsafe { nil } }
		false_ := C.PyBool_FromLong(0)
		if false_ == unsafe { nil } { return false_ }
		status := fixture_set(first, 'active', false_)
		drop(false_)
		if status != 0 { return unsafe { nil } }
		return py_none()
	}
	if op == 'enter' { return c.fixture_enter(first, C.PyTuple_GetItem(values, 1)) }
	if op == 'exit' { return fixture_exit(first, C.PyTuple_GetItem(values, 1)) }
	if op == 'observe' {
		key := vulkan_literal('observation')
		if key == unsafe { nil } { return key }
		present := C.PySequence_Contains(first, key)
		drop(key)
		if present < 0 { return unsafe { nil } }
		if present != 0 {
			target := vulkan_attr(C.PyTuple_GetItem(values, 1), 'append')
			if target == unsafe { nil } { return target }
			value := vulkan_item(first, 'observation')
			if value == unsafe { nil } { drop(target); return value }
			result := vulkan_call(target, [value])
			drop(value)
			drop(target)
			return result
		}
		return py_none()
	}
	if op == 'conversion' {
		pair := fixture_pair('completed', 'completed_stdout', true)
		if pair == unsafe { nil } { return pair }
		matched := C.PySequence_Contains(pair, first)
		drop(pair)
		if matched < 0 { return unsafe { nil } }
		if matched != 0 { return vulkan_literal('completed') }
		for name in ['path', 'paths'] {
			matched_name := c.matches(first, name)
			if matched_name < 0 { return unsafe { nil } }
			if matched_name != 0 { return vulkan_literal(name) }
		}
		return vulkan_literal('value')
	}
	if op == 'completed_options' {
		none_ := py_none()
		is_none := first == none_
		drop(none_)
		if is_none { return C.PyDict_New() }
		return vulkan_dictionary('stdout', first)
	}
	if op == 'completed' {
		provider := vulkan_attr(first, 'subprocess')
		if provider == unsafe { nil } { return provider }
		target := vulkan_attr(provider, 'CompletedProcess')
		drop(provider)
		if target == unsafe { nil } { return target }
		index := C.PyLong_FromLongLong(0)
		if index == unsafe { nil } { drop(target); return index }
		command := C.PyObject_GetItem(C.PyTuple_GetItem(values, 1), index)
		drop(index)
		if command == unsafe { nil } { drop(target); return command }
		zero := C.PyLong_FromLongLong(0)
		if zero == unsafe { nil } { drop(command); drop(target); return zero }
		args := C.PyTuple_New(2)
		if args == unsafe { nil } { drop(zero); drop(command); drop(target); return args }
		C.PyTuple_SetItem(args, 0, command)
		C.PyTuple_SetItem(args, 1, zero)
		keywords := C.PyDict_Copy(C.PyTuple_GetItem(values, 2))
		if keywords == unsafe { nil } { drop(args); drop(target); return keywords }
		result := C.PyObject_Call(target, args, keywords)
		drop(keywords)
		drop(args)
		drop(target)
		return result
	}
	if op == 'completed_result' {
		matched := c.matches(C.PyTuple_GetItem(values, 1), 'completed_stdout')
		if matched < 0 { return unsafe { nil } }
		if matched != 0 { return vulkan_attr(first, 'stdout') }
		return own(first)
	}
	if op == 'path' {
		target := c.resolve('Path')
		if target == unsafe { nil } { return target }
		result := vulkan_call(target, [first])
		drop(target)
		return result
	}
	return py_none()
}
