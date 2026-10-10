// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

fn C.PyObject_GetItem(voidptr, voidptr) voidptr
fn C.PyObject_GetAttr(voidptr, voidptr) voidptr
fn C.PyList_Append(voidptr, voidptr) i32
fn C.PyList_Insert(voidptr, isize, voidptr) i32
fn C.PyList_AsTuple(voidptr) voidptr
fn C.PyDict_SetItem(voidptr, voidptr, voidptr) i32
fn C.PyDict_GetItemWithError(voidptr, voidptr) voidptr
fn C.PyNumber_Subtract(voidptr, voidptr) voidptr
fn C.PySequence_Contains(voidptr, voidptr) i32
fn C.PyObject_RichCompare(voidptr, voidptr, i32) voidptr
fn C.PyEval_GetBuiltins() voidptr
fn C.PyUnicode_InternFromString(&char) voidptr
fn C.PyNumber_Add(voidptr, voidptr) voidptr
fn C.PyNumber_TrueDivide(voidptr, voidptr) voidptr
fn C.PyObject_SetItem(voidptr, voidptr, voidptr) i32
fn C.PyErr_NoMemory() voidptr
fn C.GC_thread_is_registered() i32
fn C.GC_allow_register_threads()
fn C.GC_get_stack_base(voidptr) i32
fn C.GC_register_my_thread(voidptr) i32
fn C.GC_unregister_my_thread() i32

__global vulkan_literals = map[string]voidptr{}

fn vulkan_literal(text string) voidptr {
	if value := vulkan_literals[text] { return own(value) }
	mut identifier := text.len != 0
	for ch in text {
		if !((ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || (ch >= `0` && ch <= `9`) || ch == `_`) { identifier = false }
	}
	value := if identifier { unsafe { C.PyUnicode_InternFromString(text.str) } } else { py_string(text) }
	if value != unsafe { nil } { vulkan_literals[text] = own(value) }
	return value
}

struct VulkanContext {
	sdk voidptr
	builtins voidptr
	row voidptr
	namespace voidptr
	values voidptr
	keywords voidptr
	decoder voidptr
	invoke voidptr
	raise_ voidptr
	owners voidptr
	pins voidptr
}

fn vulkan_attr(value voidptr, name string) voidptr {
	key := vulkan_literal(name)
	if key == unsafe { nil } { return key }
	result := C.PyObject_GetAttr(value, key)
	drop(key)
	return result
}

fn (c &VulkanContext) pin(names []string, values []voidptr) {
	if !pending_error() { return }
	mut kind := voidptr(0)
	mut error_ := voidptr(0)
	mut traceback := voidptr(0)
	C.PyErr_Fetch(&kind, &error_, &traceback)
	scope := C.PyDict_New()
	if scope != unsafe { nil } {
		for i, name in names {
			if values[i] != unsafe { nil } { unsafe { C.PyDict_SetItemString(scope, name.str, values[i]) } }
		}
		if !pending_error() { C.PyList_Insert(c.pins, 0, scope) }
		drop(scope)
	}
	C.PyErr_Restore(kind, error_, traceback)
}

fn (c &VulkanContext) resolve(name string) voidptr {
	key := vulkan_literal(name)
	if key == unsafe { nil } { return key }
	mut value := C.PyDict_GetItemWithError(c.sdk, key)
	if value == unsafe { nil } && !pending_error() {
		value = C.PyDict_GetItemWithError(c.builtins, key)
	}
	drop(key)
	if pending_error() { return unsafe { nil } }
	if value == unsafe { nil } {
		message := py_string("name '" + name + "' is not defined")
		if message == unsafe { nil } { return message }
		C.PyErr_SetObject(unsafe { voidptr(C.PyExc_NameError) }, message)
		drop(message)
		return unsafe { nil }
	}
	return own(value)
}

fn vulkan_call(target voidptr, values []voidptr) voidptr {
	args := C.PyTuple_New(values.len)
	if args == unsafe { nil } { return args }
	for i, value in values { C.PyTuple_SetItem(args, i, own(value)) }
	result := C.PyObject_Call(target, args, unsafe { nil })
	drop(args)
	return result
}

fn vulkan_method(value voidptr, name string, args []voidptr) voidptr {
	target := vulkan_attr(value, name)
	if target == unsafe { nil } { return target }
	result := vulkan_call(target, args)
	drop(target)
	return result
}

// Consume a temporary receiver after lookup, before a detached method call.
fn vulkan_temporary_method(value voidptr, name string, args []voidptr) voidptr {
	target := vulkan_attr(value, name)
	drop(value)
	if target == unsafe { nil } { return target }
	result := vulkan_call(target, args)
	drop(target)
	return result
}

fn vulkan_item(value voidptr, name string) voidptr {
	key := vulkan_literal(name)
	if key == unsafe { nil } { return key }
	result := C.PyObject_GetItem(value, key)
	drop(key)
	return result
}

fn (c &VulkanContext) invoke_target(target voidptr, keywords bool) voidptr {
	if target == unsafe { nil } { return target }
	empty := if keywords { own(c.keywords) } else { C.PyDict_New() }
	if empty == unsafe { nil } { drop(target); return empty }
	result := vulkan_call(c.invoke, [target, c.values, empty])
	drop(empty)
	drop(target)
	return result
}

fn (c &VulkanContext) dispatch(selected string, kind voidptr) voidptr {
	for name in ['resolver', 'run', 'check_output', 'json_loads', 'json_dumps',
		'equal', 'symlink', 'copy2', 'temporary', 'print'] {
		if name != selected { continue }
		if name == 'resolver' { return c.resolver() }
		if name == 'temporary' { return c.temporary() }
		if name in ['run', 'check_output', 'copy2'] {
			provider := vulkan_item(c.namespace, if name == 'copy2' { 'shutil' } else { 'subprocess' })
			if provider == unsafe { nil } { return provider }
			target := vulkan_attr(provider, name)
			drop(provider)
			return c.invoke_target(target, name != 'copy2')
		}
		if name in ['json_dumps', 'equal'] {
			provider := c.resolve(if name == 'equal' { 'operator' } else { 'json' })
			if provider == unsafe { nil } { return provider }
			target := vulkan_attr(provider, if name == 'equal' { 'eq' } else { 'dumps' })
			drop(provider)
			return c.invoke_target(target, name == 'json_dumps')
		}
		if name == 'json_loads' {
			provider := c.resolve('json')
			if provider == unsafe { nil } { return provider }
			target := vulkan_attr(provider, 'loads')
			drop(provider)
			if target == unsafe { nil } { return target }
			bytes_ := c.resolve('bytes')
			if bytes_ == unsafe { nil } { drop(target); return bytes_ }
			decoder := vulkan_attr(bytes_, 'fromhex')
			drop(bytes_)
			if decoder == unsafe { nil } { drop(target); return decoder }
			data := vulkan_item(c.row, 'data_hex')
			if data == unsafe { nil } { drop(decoder); drop(target); return data }
			decoded := vulkan_call(decoder, [data])
			drop(data)
			drop(decoder)
			if decoded == unsafe { nil } { drop(target); return decoded }
			text := vulkan_temporary_method(decoded, 'decode', [])
			if text == unsafe { nil } { drop(target); return text }
			result := vulkan_call(target, [text])
			drop(text)
			drop(target)
			return result
		}
		if name == 'symlink' {
			index := C.PyLong_FromLongLong(1)
			if index == unsafe { nil } { return index }
			owner := C.PyObject_GetItem(c.values, index)
			drop(index)
			if owner == unsafe { nil } { return owner }
			target := vulkan_attr(owner, 'symlink_to')
			drop(owner)
			if target == unsafe { nil } { return target }
			zero := C.PyLong_FromLongLong(0)
			if zero == unsafe { nil } { drop(target); return zero }
			value := C.PyObject_GetItem(c.values, zero)
			drop(zero)
			if value == unsafe { nil } { drop(target); return value }
			result := vulkan_call(target, [value])
			drop(value)
			drop(target)
			return result
		}
		if name == 'print' {
			result := c.invoke_target(c.resolve('print'), true)
			if result == unsafe { nil } { return result }
			drop(result)
			return py_none()
		}
	}
	kind_ := c.resolve('RuntimeError')
	if kind_ == unsafe { nil } { return kind_ }
	prefix := vulkan_literal('unknown Vulkan primitive: ')
	if prefix == unsafe { nil } { drop(kind_); return prefix }
	message := C.PyNumber_Add(prefix, kind)
	drop(prefix)
	if message == unsafe { nil } { drop(kind_); return message }
	error_ := vulkan_call(kind_, [message])
	drop(message)
	drop(kind_)
	if error_ == unsafe { nil } { return error_ }
	result := vulkan_call(c.raise_, [error_])
	drop(error_)
	return result
}

pub fn vulkan_entry(operation &char, sdk voidptr, arguments voidptr, pins voidptr) voidptr {
	C.GC_allow_register_threads()
	mut registered := false
	if C.GC_thread_is_registered() == 0 {
		mut base := C.GC_stack_base{}
		if C.GC_get_stack_base(&base) != 0 { return C.PyErr_NoMemory() }
		registered = C.GC_register_my_thread(&base) == 0
		if !registered { return C.PyErr_NoMemory() }
	}
	defer { if registered { C.GC_unregister_my_thread() } }
	name := unsafe { operation.vstring() }
	if name == 'select' {
		c := VulkanContext{ sdk: sdk, builtins: C.PyEval_GetBuiltins(), pins: pins }
		for tag in ['resolver', 'run', 'check_output', 'json_loads', 'json_dumps', 'equal', 'symlink', 'copy2', 'temporary', 'retire', 'context_exit', 'print'] {
			matched := c.matches(C.PyTuple_GetItem(arguments, 0), tag)
			if matched < 0 { return unsafe { nil } }
			if matched != 0 { return vulkan_literal(tag) }
		}
		return vulkan_literal('unknown')
	}
	if name == 'fixture' { return vulkan_fixture(arguments, pins) }
	if name == 'preparation' { return vulkan_preparation(arguments, pins) }
	if name in ['received', 'contains', 'value', 'failed', 'send'] {
		c := VulkanContext{ sdk: sdk, builtins: C.PyEval_GetBuiltins(), pins: pins }
		return c.protocol(name, arguments)
	}
	if name == 'failure' {
		c := VulkanContext{ sdk: sdk, builtins: C.PyEval_GetBuiltins(), pins: pins }
		return c.failure(C.PyTuple_GetItem(arguments, 0), C.PyTuple_GetItem(arguments, 1))
	}
	c := VulkanContext{
		sdk: sdk
		builtins: C.PyEval_GetBuiltins()
		row: C.PyTuple_GetItem(arguments, 1)
		namespace: C.PyTuple_GetItem(arguments, 2)
		values: C.PyTuple_GetItem(arguments, 3)
		keywords: C.PyTuple_GetItem(arguments, 4)
		decoder: C.PyTuple_GetItem(arguments, 5)
		invoke: C.PyTuple_GetItem(arguments, 6)
		raise_: C.PyTuple_GetItem(arguments, 7)
		owners: C.PyTuple_GetItem(arguments, 8)
		pins: pins
	}
	return c.dispatch(string_value(C.PyTuple_GetItem(arguments, 9)), C.PyTuple_GetItem(arguments, 0))
}
