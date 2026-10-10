// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

fn vulkan_dictionary(name string, value voidptr) voidptr {
	result := C.PyDict_New()
	if result == unsafe { nil } { return result }
	key := vulkan_literal(name)
	if key == unsafe { nil } { drop(result); return key }
	status := C.PyDict_SetItem(result, key, value)
	drop(key)
	if status != 0 { drop(result); return unsafe { nil } }
	return result
}

fn (c &VulkanContext) protocol(operation string, arguments voidptr) voidptr {
	first := C.PyTuple_GetItem(arguments, 0)
	if operation == 'contains' {
		present := C.PySequence_Contains(first, C.PyTuple_GetItem(arguments, 1))
		if present < 0 { return unsafe { nil } }
		return C.PyBool_FromLong(present)
	}
	if operation == 'value' { return vulkan_dictionary('value', first) }
	if operation == 'failed' {
		appended := vulkan_method(first, 'append', [C.PyTuple_GetItem(arguments, 1)])
		if appended == unsafe { nil } { return appended }
		drop(appended)
		length_fn := c.resolve('len')
		if length_fn == unsafe { nil } { return length_fn }
		length := vulkan_call(length_fn, [first])
		drop(length_fn)
		if length == unsafe { nil } { return length }
		one := C.PyLong_FromLongLong(1)
		if one == unsafe { nil } { drop(length); return one }
		index := C.PyNumber_Subtract(length, one)
		drop(length)
		drop(one)
		if index == unsafe { nil } { return index }
		failure := vulkan_dictionary('binding_error', index)
		drop(index)
		if failure == unsafe { nil } { return failure }
		result := vulkan_dictionary('error', failure)
		drop(failure)
		return result
	}
	if operation == 'received' {
		child := C.PyTuple_GetItem(arguments, 1)
		truth := C.PyObject_IsTrue(first)
		if truth < 0 { return unsafe { nil } }
		if truth == 0 {
			waited := vulkan_method(child, 'wait', [])
			if waited == unsafe { nil } { return waited }
			drop(waited)
			factory := c.resolve('RuntimeError')
			if factory == unsafe { nil } { return factory }
			message := vulkan_literal('native Vulkan stager ended before returning a result')
			if message == unsafe { nil } { drop(factory); return message }
			error_ := vulkan_call(factory, [message])
			drop(message)
			drop(factory)
			if error_ == unsafe { nil } { return error_ }
			result := vulkan_call(C.PyTuple_GetItem(arguments, 2), [error_])
			drop(error_)
			return result
		}
		provider := c.resolve('json')
		if provider == unsafe { nil } { return provider }
		target := vulkan_attr(provider, 'loads')
		drop(provider)
		if target == unsafe { nil } { return target }
		result := vulkan_call(target, [first])
		drop(target)
		return result
	}
	// Original LOAD_METHOD consumes each temporary stdin receiver before the
	// JSON encoder (and before either detached method callback) runs.
	input := vulkan_attr(first, 'stdin')
	if input == unsafe { nil } { return input }
	writer := vulkan_attr(input, 'write')
	drop(input)
	if writer == unsafe { nil } { return writer }
	provider := c.resolve('json')
	if provider == unsafe { nil } { drop(writer); return provider }
	encoder := vulkan_attr(provider, 'dumps')
	drop(provider)
	if encoder == unsafe { nil } { drop(writer); return encoder }
	encoded := vulkan_call(encoder, [C.PyTuple_GetItem(arguments, 1)])
	drop(encoder)
	if encoded == unsafe { nil } { drop(writer); return encoded }
	newline := vulkan_literal('\n')
	if newline == unsafe { nil } { drop(encoded); drop(writer); return newline }
	text := C.PyNumber_Add(encoded, newline)
	drop(encoded)
	drop(newline)
	if text == unsafe { nil } { drop(writer); return text }
	written := vulkan_call(writer, [text])
	drop(text)
	drop(writer)
	if written == unsafe { nil } { return written }
	drop(written)
	second_input := vulkan_attr(first, 'stdin')
	if second_input == unsafe { nil } { return second_input }
	flushed := vulkan_temporary_method(second_input, 'flush', [])
	if flushed == unsafe { nil } { return flushed }
	drop(flushed)
	return py_none()
}

fn (c &VulkanContext) temporary() voidptr {
	mut owner := voidptr(0)
	mut entered := voidptr(0)
	defer {
		c.pin(['owner', 'entered'], [owner, entered])
		drop(owner)
		drop(entered)
	}
	provider := c.resolve('tempfile')
	if provider == unsafe { nil } { return provider }
	factory := vulkan_attr(provider, 'TemporaryDirectory')
	drop(provider)
	if factory == unsafe { nil } { return factory }
	empty := C.PyList_New(0)
	if empty == unsafe { nil } { drop(factory); return empty }
	owner = vulkan_call(c.invoke, [factory, empty, c.keywords])
	drop(empty)
	drop(factory)
	if owner == unsafe { nil } { return owner }
	entered = vulkan_method(owner, '__enter__', [])
	if entered == unsafe { nil } { return entered }
	identifier := c.resolve('id')
	if identifier == unsafe { nil } { return identifier }
	ident := vulkan_call(identifier, [owner])
	drop(identifier)
	if ident == unsafe { nil } { return ident }
	status := C.PyObject_SetItem(c.owners, ident, owner)
	drop(ident)
	if status != 0 { return unsafe { nil } }
	result := vulkan_dictionary('owner', owner)
	if result == unsafe { nil } { return result }
	key := vulkan_literal('entered')
	if key == unsafe { nil } { drop(result); return key }
	stored := C.PyDict_SetItem(result, key, entered)
	drop(key)
	if stored != 0 { drop(result); return unsafe { nil } }
	return result
}

fn (c &VulkanContext) resolver() voidptr {
	mut spec := voidptr(0)
	mut result := voidptr(0)
	defer {
		c.pin(['spec', 'result'], [spec, result])
		drop(spec)
		drop(result)
	}
	provider := c.resolve('importlib')
	if provider == unsafe { nil } { return provider }
	util := vulkan_attr(provider, 'util')
	drop(provider)
	if util == unsafe { nil } { return util }
	factory := vulkan_attr(util, 'spec_from_file_location')
	drop(util)
	if factory == unsafe { nil } { return factory }
	name := vulkan_literal('vinix_debian_root')
	if name == unsafe { nil } { drop(factory); return name }
	root := c.resolve('ROOT')
	if root == unsafe { nil } { drop(name); drop(factory); return root }
	leaf := vulkan_literal('build-support/debian-root.py')
	if leaf == unsafe { nil } { drop(root); drop(name); drop(factory); return leaf }
	path := C.PyNumber_TrueDivide(root, leaf)
	drop(root)
	drop(leaf)
	if path == unsafe { nil } { drop(name); drop(factory); return path }
	spec = vulkan_call(factory, [name, path])
	drop(path)
	drop(name)
	drop(factory)
	if spec == unsafe { nil } { return spec }
	provider2 := c.resolve('importlib')
	if provider2 == unsafe { nil } { return provider2 }
	util2 := vulkan_attr(provider2, 'util')
	drop(provider2)
	if util2 == unsafe { nil } { return util2 }
	creator := vulkan_attr(util2, 'module_from_spec')
	drop(util2)
	if creator == unsafe { nil } { return creator }
	result = vulkan_call(creator, [spec])
	drop(creator)
	if result == unsafe { nil } { return result }
	sys := c.resolve('sys')
	if sys == unsafe { nil } { return sys }
	modules := vulkan_attr(sys, 'modules')
	drop(sys)
	if modules == unsafe { nil } { return modules }
	spec_name := vulkan_attr(spec, 'name')
	if spec_name == unsafe { nil } { drop(modules); return spec_name }
	status := C.PyObject_SetItem(modules, spec_name, result)
	drop(modules)
	drop(spec_name)
	if status != 0 { return unsafe { nil } }
	loader := vulkan_attr(spec, 'loader')
	if loader == unsafe { nil } { return loader }
	executor := vulkan_attr(loader, 'exec_module')
	drop(loader)
	if executor == unsafe { nil } { return executor }
	executed := vulkan_call(executor, [result])
	drop(executor)
	if executed == unsafe { nil } { return executed }
	drop(executed)
	return own(result)
}
