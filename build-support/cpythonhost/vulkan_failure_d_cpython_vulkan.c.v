// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

fn (c &VulkanContext) matches(value voidptr, label string) i32 {
	text := vulkan_literal(label)
	if text == unsafe { nil } { return -1 }
	compared := C.PyObject_RichCompare(value, text, 2)
	drop(text)
	if compared == unsafe { nil } { return -1 }
	truth := C.PyObject_IsTrue(compared)
	drop(compared)
	return truth
}

fn (c &VulkanContext) filesystem(value voidptr, field string) voidptr {
	module_ := c.resolve('os')
	if module_ == unsafe { nil } { return module_ }
	target := vulkan_attr(module_, 'fsdecode')
	drop(module_)
	if target == unsafe { nil } { return target }
	factory := c.resolve('bytes')
	if factory == unsafe { nil } { drop(target); return factory }
	decoder := vulkan_attr(factory, 'fromhex')
	drop(factory)
	if decoder == unsafe { nil } { drop(target); return decoder }
	input := if field == '' { own(value) } else { vulkan_item(value, field) }
	if input == unsafe { nil } { drop(decoder); drop(target); return input }
	bytes_ := vulkan_call(decoder, [input])
	drop(input)
	drop(decoder)
	if bytes_ == unsafe { nil } { drop(target); return bytes_ }
	result := vulkan_call(target, [bytes_])
	drop(bytes_)
	drop(target)
	return result
}

fn (c &VulkanContext) copied_errors(failure voidptr) voidptr {
	entries := vulkan_item(failure, 'entries')
	if entries == unsafe { nil } { return entries }
	iterator := C.PyObject_GetIter(entries)
	drop(entries)
	if iterator == unsafe { nil } { return iterator }
	result := C.PyList_New(0)
	if result == unsafe { nil } { c.pin(['.0'], [iterator]); drop(iterator); return result }
	mut source := voidptr(0)
	mut target := voidptr(0)
	mut message := voidptr(0)
	triplet := c.resolve('_vulkan_triplet')
	if triplet == unsafe { nil } { c.pin(['.0'], [iterator]); drop(iterator); drop(result); return triplet }
	for {
		row := C.PyIter_Next(iterator)
		if row == unsafe { nil } { break }
		values := vulkan_call(triplet, [row])
		drop(row)
		if values == unsafe { nil } { break }
		new_source := own(C.PyTuple_GetItem(values, 0))
		new_target := own(C.PyTuple_GetItem(values, 1))
		new_message := own(C.PyTuple_GetItem(values, 2))
		drop(values)
		drop(source)
		source = new_source
		drop(target)
		target = new_target
		drop(message)
		message = new_message
		converted_source := c.filesystem(source, '')
		if converted_source == unsafe { nil } { break }
		converted_target := c.filesystem(target, '')
		if converted_target == unsafe { nil } { drop(converted_source); break }
		entry := C.PyTuple_New(3)
		if entry == unsafe { nil } { drop(converted_target); drop(converted_source); break }
		C.PyTuple_SetItem(entry, 0, converted_source)
		C.PyTuple_SetItem(entry, 1, converted_target)
		C.PyTuple_SetItem(entry, 2, own(message))
		status := C.PyList_Append(result, entry)
		drop(entry)
		if status != 0 { break }
	}
	c.pin(['.0', 'source', 'target', 'message'], [iterator, source, target, message])
	drop(source)
	drop(target)
	drop(message)
	drop(iterator)
	drop(triplet)
	if pending_error() { drop(result); return unsafe { nil } }
	return result
}

fn (c &VulkanContext) failure(failure voidptr, errors voidptr) voidptr {
	key := vulkan_literal('binding_error')
	if key == unsafe { nil } { return key }
	bound := C.PySequence_Contains(failure, key)
	drop(key)
	if bound < 0 { return unsafe { nil } }
	if bound != 0 {
		index := vulkan_item(failure, 'binding_error')
		if index == unsafe { nil } { return index }
		result := C.PyObject_GetItem(errors, index)
		drop(index)
		return result
	}
	kind := vulkan_item(failure, 'kind')
	if kind == unsafe { nil } { return kind }
	mut args := voidptr(0)
	defer {
		c.pin(['kind', 'args'], [kind, args])
		drop(kind)
		drop(args)
	}
	for name in ['OSError', 'CopyError', 'UnicodeDecodeError', 'StopIteration'] {
		matched := c.matches(kind, name)
		if matched < 0 { return unsafe { nil } }
		if matched == 0 { continue }
		if name == 'OSError' {
			errno1 := vulkan_item(failure, 'errno')
			if errno1 == unsafe { nil } { return errno1 }
			module_ := c.resolve('os')
			if module_ == unsafe { nil } { drop(errno1); return module_ }
			formatter := vulkan_attr(module_, 'strerror')
			drop(module_)
			if formatter == unsafe { nil } { drop(errno1); return formatter }
			errno2 := vulkan_item(failure, 'errno')
			if errno2 == unsafe { nil } { drop(formatter); drop(errno1); return errno2 }
			text := vulkan_call(formatter, [errno2])
			drop(errno2)
			drop(formatter)
			if text == unsafe { nil } { drop(errno1); return text }
			args = C.PyList_New(2)
			if args == unsafe { nil } { drop(text); drop(errno1); return args }
			C.PyList_SetItem(args, 0, errno1)
			C.PyList_SetItem(args, 1, text)
			filename_key := vulkan_literal('filename')
			if filename_key == unsafe { nil } { return filename_key }
			filename_flag := vulkan_method(failure, 'get', [filename_key])
			drop(filename_key)
			if filename_flag == unsafe { nil } { return filename_flag }
			filename := C.PyObject_IsTrue(filename_flag)
			drop(filename_flag)
			if filename < 0 { return unsafe { nil } }
			if filename != 0 {
				value := c.filesystem(failure, 'filename')
				if value == unsafe { nil } { return value }
				status := C.PyList_Append(args, value)
				drop(value)
				if status != 0 { return unsafe { nil } }
			}
			filename2_key := vulkan_literal('filename2')
			if filename2_key == unsafe { nil } { return filename2_key }
			has_second := C.PySequence_Contains(failure, filename2_key)
			drop(filename2_key)
			if has_second < 0 { return unsafe { nil } }
			if has_second != 0 {
				length_fn := c.resolve('len')
				if length_fn == unsafe { nil } { return length_fn }
				length := vulkan_call(length_fn, [args])
				drop(length_fn)
				if length == unsafe { nil } { return length }
				two := C.PyLong_FromLongLong(2)
				if two == unsafe { nil } { drop(length); return two }
				comparison := C.PyObject_RichCompare(length, two, 2)
				drop(length)
				drop(two)
				if comparison == unsafe { nil } { return comparison }
				exact := C.PyObject_IsTrue(comparison)
				drop(comparison)
				if exact < 0 { return unsafe { nil } }
				if exact != 0 {
					none_ := py_none()
					status := C.PyList_Append(args, none_)
					drop(none_)
					if status != 0 { return unsafe { nil } }
				}
				value := c.filesystem(failure, 'filename2')
				if value == unsafe { nil } { return value }
				none_ := py_none()
				status := C.PyList_Append(args, none_)
				drop(none_)
				if status != 0 { drop(value); return unsafe { nil } }
				status2 := C.PyList_Append(args, value)
				drop(value)
				if status2 != 0 { return unsafe { nil } }
			}
			factory := c.resolve('OSError')
			if factory == unsafe { nil } { return factory }
			arguments := C.PyList_AsTuple(args)
			if arguments == unsafe { nil } { drop(factory); return arguments }
			result := C.PyObject_Call(factory, arguments, unsafe { nil })
			drop(arguments)
			drop(factory)
			return result
		}
		if name == 'CopyError' {
			module_ := c.resolve('shutil')
			if module_ == unsafe { nil } { return module_ }
			factory := vulkan_attr(module_, 'Error')
			drop(module_)
			if factory == unsafe { nil } { return factory }
			entries := c.copied_errors(failure)
			if entries == unsafe { nil } { drop(factory); return entries }
			result := vulkan_call(factory, [entries])
			drop(entries)
			drop(factory)
			return result
		}
		if name == 'StopIteration' {
			factory := c.resolve('StopIteration')
			if factory == unsafe { nil } { return factory }
			result := vulkan_call(factory, [])
			drop(factory)
			return result
		}
		factory := c.resolve('UnicodeDecodeError')
		if factory == unsafe { nil } { return factory }
		encoding := vulkan_literal('utf-8')
		if encoding == unsafe { nil } { drop(factory); return encoding }
		bytes_ := c.resolve('bytes')
		if bytes_ == unsafe { nil } { drop(encoding); drop(factory); return bytes_ }
		decoder := vulkan_attr(bytes_, 'fromhex')
		drop(bytes_)
		if decoder == unsafe { nil } { drop(encoding); drop(factory); return decoder }
		data := vulkan_item(failure, 'data')
		if data == unsafe { nil } { drop(decoder); drop(encoding); drop(factory); return data }
		decoded := vulkan_call(decoder, [data])
		drop(data)
		drop(decoder)
		if decoded == unsafe { nil } { drop(encoding); drop(factory); return decoded }
		start := vulkan_item(failure, 'start')
		if start == unsafe { nil } { drop(decoded); drop(encoding); drop(factory); return start }
		end := vulkan_item(failure, 'end')
		if end == unsafe { nil } { drop(start); drop(decoded); drop(encoding); drop(factory); return end }
		reason := vulkan_item(failure, 'reason')
		if reason == unsafe { nil } { drop(end); drop(start); drop(decoded); drop(encoding); drop(factory); return reason }
		result := vulkan_call(factory, [encoding, decoded, start, end, reason])
		drop(reason)
		drop(end)
		drop(start)
		drop(decoded)
		drop(encoding)
		drop(factory)
		return result
	}
	factories := C.PyDict_New()
	if factories == unsafe { nil } { return factories }
	for name in ['SystemExit', 'ArgumentError', 'ValueError', 'RuntimeError', 'StopIteration', 'AttributeError'] {
		key_ := vulkan_literal(name)
		if key_ == unsafe { nil } { drop(factories); return key_ }
		factory := c.resolve(name)
		if factory == unsafe { nil } { drop(key_); drop(factories); return factory }
		status := C.PyDict_SetItem(factories, key_, factory)
		drop(factory)
		drop(key_)
		if status != 0 { drop(factories); return unsafe { nil } }
	}
	factory := C.PyObject_GetItem(factories, kind)
	drop(factories)
	if factory == unsafe { nil } { return factory }
	message := vulkan_item(failure, 'message')
	if message == unsafe { nil } { drop(factory); return message }
	result := vulkan_call(factory, [message])
	drop(message)
	drop(factory)
	return result
}
