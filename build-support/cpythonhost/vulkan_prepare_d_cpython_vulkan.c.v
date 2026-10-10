// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

fn C.PyCapsule_New(voidptr, &char, voidptr) voidptr
fn C.PyCapsule_GetPointer(voidptr, &char) voidptr
fn C.vinix_vulkan_prepare_dispose(voidptr)

struct VulkanPrepareExpression {
mut:
	values [2]voidptr
}

pub fn vulkan_prepare_take(capsule voidptr, index i32) voidptr {
	mut state := unsafe { &VulkanPrepareExpression(C.PyCapsule_GetPointer(capsule, c'vinix.dota.prepare.expression')) }
	if state == unsafe { nil } { return unsafe { nil } }
	if index < 0 || index > 1 || state.values[index] == unsafe { nil } {
		message := py_string('invalid Dota preparation operand')
		if message == unsafe { nil } { return message }
		C.PyErr_SetObject(unsafe { voidptr(C.PyExc_TypeError) }, message)
		drop(message)
		return unsafe { nil }
	}
	value := state.values[index]
	state.values[index] = unsafe { nil }
	return value
}

// The capsule owns its two references until the Python expression transfers
// them onto its operand stack. Its traceback retains no consumed references.
pub fn vulkan_prepare_dispose(capsule voidptr) {
	state := unsafe { &VulkanPrepareExpression(C.PyCapsule_GetPointer(capsule, c'vinix.dota.prepare.expression')) }
	if state == unsafe { nil } { return }
	drop(state.values[1])
	drop(state.values[0])
	unsafe { C.free(state) }
}

fn vulkan_prepare_expression(target voidptr, value voidptr) voidptr {
	if value == unsafe { nil } { drop(target); return value }
	mut state := unsafe { &VulkanPrepareExpression(C.malloc(sizeof(VulkanPrepareExpression))) }
	if state == unsafe { nil } {
		C.PyErr_NoMemory()
		drop(value)
		drop(target)
		return unsafe { nil }
	}
	unsafe { *state = VulkanPrepareExpression{ values: [target, value]! } }
	capsule := C.PyCapsule_New(state, c'vinix.dota.prepare.expression', voidptr(C.vinix_vulkan_prepare_dispose))
	if capsule == unsafe { nil } {
		drop(value)
		drop(target)
		unsafe { C.free(state) }
	}
	return capsule
}

fn prepare_at(args voidptr, index i64) voidptr {
	key := C.PyLong_FromLongLong(index)
	if key == unsafe { nil } { return key }
	result := C.PyObject_GetItem(args, key)
	drop(key)
	return result
}

fn (c &VulkanContext) prepare_path(args voidptr, index i64) voidptr {
	factory := c.resolve('Path')
	if factory == unsafe { nil } { return factory }
	value := prepare_at(args, index)
	if value == unsafe { nil } { drop(factory); return value }
	result := vulkan_call(factory, [value])
	drop(value)
	drop(factory)
	return result
}

fn (c &VulkanContext) prepare_target(module_ string, method string) voidptr {
	provider := c.resolve(module_)
	if provider == unsafe { nil } { return provider }
	target := vulkan_attr(provider, method)
	drop(provider)
	return target
}

fn (c &VulkanContext) prepare_invoke(target voidptr, values voidptr, names []string, operands []voidptr) voidptr {
	keywords := C.PyDict_New()
	if keywords == unsafe { nil } { return keywords }
	for i, name in names {
		key := vulkan_literal(name)
		if key == unsafe { nil } { drop(keywords); return key }
		status := C.PyDict_SetItem(keywords, key, operands[i])
		drop(key)
		if status != 0 { drop(keywords); return unsafe { nil } }
	}
	result := vulkan_call(c.invoke, [target, values, keywords])
	drop(keywords)
	return result
}

fn (c &VulkanContext) prepare_work(operation string, row voidptr, context voidptr, args voidptr) voidptr {
	if operation in ['reference_path', 'attribute', 'test'] {
		getter := c.resolve('getattr')
		if getter == unsafe { nil } { return getter }
		owner := if operation == 'test' { c.prepare_path(args, 0) } else {
			vulkan_item(context, if operation == 'attribute' { 'namespace' } else { 'current' })
		}
		if owner == unsafe { nil } { drop(getter); return owner }
		name := vulkan_item(row, if operation == 'attribute' { 'name' } else { 'function' })
		if name == unsafe { nil } { drop(owner); drop(getter); return name }
		target := vulkan_call(getter, [owner, name])
		drop(name)
		drop(owner)
		drop(getter)
		if target == unsafe { nil } || operation == 'attribute' { return target }
		result := if operation == 'test' { vulkan_call(target, []) } else { c.prepare_invoke(target, args, [], []) }
		drop(target)
		return result
	}
	if operation in ['read_text', 'write_text', 'write_bytes', 'mkdir', 'unlink', 'symlink', 'rename', 'chmod', 'size'] {
		path := c.prepare_path(args, 0)
		if path == unsafe { nil } { return path }
		target := vulkan_attr(path, if operation == 'size' { 'stat' } else if operation == 'symlink' { 'symlink_to' } else { operation })
		drop(path)
		if target == unsafe { nil } { return target }
		mut first := voidptr(0)
		mut second := voidptr(0)
		mut result := voidptr(0)
		if operation in ['write_text', 'symlink', 'rename', 'chmod'] {
			first = if operation == 'rename' { c.prepare_path(args, 1) } else if operation == 'chmod' { vulkan_item(row, 'mode') } else { prepare_at(args, 1) }
			if first != unsafe { nil } { result = vulkan_call(target, [first]) }
		} else if operation == 'write_bytes' {
			decoder := c.prepare_target('bytes', 'fromhex')
			if decoder != unsafe { nil } {
				data := vulkan_item(row, 'data')
				if data != unsafe { nil } { first = vulkan_call(decoder, [data]); drop(data) }
				drop(decoder)
			}
			if first != unsafe { nil } { result = vulkan_call(target, [first]) }
		} else if operation == 'mkdir' {
			first = vulkan_item(row, 'parents')
			if first != unsafe { nil } { second = vulkan_item(row, 'exist_ok') }
			if second != unsafe { nil } {
				empty := C.PyTuple_New(0)
				if empty != unsafe { nil } { result = c.prepare_invoke(target, empty, ['parents', 'exist_ok'], [first, second]) }
				drop(empty)
			}
		} else { result = vulkan_call(target, []) }
		drop(second)
		drop(first)
		drop(target)
		if result == unsafe { nil } { return result }
		if operation == 'read_text' { return result }
		if operation == 'size' {
			value := vulkan_attr(result, 'st_size')
			drop(result)
			return value
		}
		drop(result)
		return py_none()
	}
	if operation in ['rmtree', 'copy2', 'copytree'] {
		target := c.prepare_target('shutil', operation)
		if target == unsafe { nil } { return target }
		first := c.prepare_path(args, 0)
		if first == unsafe { nil } { drop(target); return first }
		mut second := voidptr(0)
		mut flag := voidptr(0)
		mut result := voidptr(0)
		if operation == 'rmtree' { result = vulkan_call(target, [first]) } else {
			second = c.prepare_path(args, 1)
			if second != unsafe { nil } {
				if operation == 'copy2' { result = vulkan_call(target, [first, second]) } else {
					flag = vulkan_item(row, 'symlinks')
					if flag != unsafe { nil } {
						values := C.PyTuple_New(2)
						if values != unsafe { nil } {
							C.PyTuple_SetItem(values, 0, own(first))
							C.PyTuple_SetItem(values, 1, own(second))
							result = c.prepare_invoke(target, values, ['symlinks'], [flag])
						}
						drop(values)
					}
				}
			}
		}
		drop(flag)
		drop(second)
		drop(first)
		drop(target)
		if result == unsafe { nil } { return result }
		drop(result)
		return py_none()
	}
	if operation in ['system', 'pid', 'executable'] {
		if operation == 'executable' { return c.prepare_target('sys', 'executable') }
		target := c.prepare_target(if operation == 'system' { 'platform' } else { 'os' }, if operation == 'system' { 'system' } else { 'getpid' })
		if target == unsafe { nil } { return target }
		result := vulkan_call(target, [])
		drop(target)
		return result
	}
	module_ := if operation in ['run', 'output'] { 'subprocess' } else if operation == 'quote' { 'shlex' } else { 'os' }
	method := if operation == 'output' { 'check_output' } else { operation }
	target := c.prepare_target(module_, method)
	if target == unsafe { nil } { return target }
	mut first := voidptr(0)
	mut second := voidptr(0)
	mut result := voidptr(0)
	if operation in ['readlink', 'quote', 'access'] {
		first = prepare_at(args, 0)
		if first != unsafe { nil } {
			if operation == 'access' {
				second = vulkan_item(row, 'mode')
				if second != unsafe { nil } { result = vulkan_call(target, [first, second]) }
			} else { result = vulkan_call(target, [first]) }
		}
	} else {
		first = vulkan_item(row, if operation == 'run' { 'check' } else { 'text' })
		if first != unsafe { nil } {
			values := C.PyTuple_New(1)
			if values != unsafe { nil } {
				C.PyTuple_SetItem(values, 0, own(args))
				result = c.prepare_invoke(target, values, [if operation == 'run' { 'check' } else { 'text' }], [first])
			}
			drop(values)
		}
	}
	drop(second)
	drop(first)
	drop(target)
	if result == unsafe { nil } { return result }
	if operation == 'run' { drop(result); return py_none() }
	return result
}

fn vulkan_preparation(arguments voidptr, pins voidptr) voidptr {
	c := VulkanContext{
		sdk: C.PyTuple_GetItem(arguments, 0)
		builtins: C.PyEval_GetBuiltins()
		invoke: C.PyTuple_GetItem(arguments, 5)
		pins: pins
	}
	operation := string_value(C.PyTuple_GetItem(arguments, 1))
	row := C.PyTuple_GetItem(arguments, 2)
	if operation == 'select' {
		for name in ['next', 'reference_path', 'open_read', 'read_handle', 'close_handle', 'attribute', 'sequence', 'path', 'test', 'list', 'read', 'read_text', 'write_text', 'write_bytes', 'mkdir', 'unlink', 'symlink', 'readlink', 'rmtree', 'copy2', 'copytree', 'rename', 'chmod', 'size', 'access', 'system', 'pid', 'executable', 'run', 'output', 'regex', 'quote', 'archive', 'truncate'] {
			matched := c.matches(row, name)
			if matched < 0 { return unsafe { nil } }
			if matched != 0 { return vulkan_literal(name) }
		}
		return vulkan_literal('unknown')
	}
	transform := c.resolve(if operation == 'attribute' { '_pack' } else if operation in ['reference_path', 'read_text', 'readlink', 'system', 'executable', 'output', 'quote'] { '_text' } else { '_objects_identity' })
	if transform == unsafe { nil } { return transform }
	value := c.prepare_work(operation, row, C.PyTuple_GetItem(arguments, 3), C.PyTuple_GetItem(arguments, 4))
	return vulkan_prepare_expression(transform, value)
}
