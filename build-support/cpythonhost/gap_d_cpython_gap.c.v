// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

fn C.PyObject_GetItem(voidptr, voidptr) voidptr
fn C.PyObject_SetItem(voidptr, voidptr, voidptr) i32
fn C.PyObject_GetAttr(voidptr, voidptr) voidptr
fn C.PyUnicode_InternFromString(&char) voidptr
fn C.PyList_Append(voidptr, voidptr) i32
fn C.PyList_AsTuple(voidptr) voidptr
fn C.PyDict_SetItem(voidptr, voidptr, voidptr) i32
fn C.PyNumber_Add(voidptr, voidptr) voidptr
fn C.PyObject_RichCompare(voidptr, voidptr, i32) voidptr
fn C.PySequence_Contains(voidptr, voidptr) i32
fn C.PySequence_List(voidptr) voidptr
fn C.PyNumber_Or(voidptr, voidptr) voidptr
fn C.PySet_New(voidptr) voidptr
fn C.PySet_Add(voidptr, voidptr) i32
fn C.PyExceptionInstance_Check(voidptr) i32
fn C.PySlice_New(voidptr, voidptr, voidptr) voidptr
fn C.PyList_Insert(voidptr, isize, voidptr) i32
fn C.PyLong_AsUnsignedLongLong(voidptr) u64
fn C.PyLong_FromUnsignedLongLong(u64) voidptr

@[c_extern]
__global C.PyExc_KeyError voidptr

struct GapLibrary {
	namespace    voidptr
	resources    voidptr
	sdk          voidptr
	argument     voidptr
	registration voidptr
	entered      voidptr
	stop_drain   voidptr
	entered_ids  voidptr
mut:
	error_pins voidptr
	pair       voidptr
}

__global gap_libraries = map[u64]&GapLibrary{}
__global gap_library_serial u64 = 1

// Own the finite fixed attribute literals for this implementation lifetime,
// like Python co_names. Dynamic row names never enter this pool.
__global gap_literal_names = map[string]voidptr{}

fn gap_literal_name(name string) voidptr {
	if value := gap_literal_names[name] { return own(value) }
	value := unsafe { C.PyUnicode_InternFromString(name.str) }
	if value != unsafe { nil } { gap_literal_names[name] = own(value) }
	return value
}

fn gap_attr(value voidptr, name string) voidptr {
	key := gap_literal_name(name)
	if key == unsafe { nil } { return key }
	result := C.PyObject_GetAttr(value, key)
	drop(key)
	return result
}

fn gap_item(value voidptr, name string) voidptr {
	key := py_string(name)
	result := C.PyObject_GetItem(value, key)
	drop(key)
	return result
}

fn gap_set(value voidptr, name string, item voidptr) {
	key := py_string(name)
	C.PyObject_SetItem(value, key, item)
	drop(key)
}

fn gap_call(target voidptr, values []voidptr) voidptr {
	args := C.PyTuple_New(values.len)
	for i, value in values { C.PyTuple_SetItem(args, i, own(value)) }
	result := C.PyObject_Call(target, args, unsafe { nil })
	drop(args)
	return result
}

fn gap_method(value voidptr, name string, args []voidptr) voidptr {
	target := gap_attr(value, name)
	if target == unsafe { nil } { return unsafe { nil } }
	result := gap_call(target, args)
	drop(target)
	return result
}

fn gap_get(value voidptr, name string, default_value voidptr) voidptr {
	target := gap_attr(value, 'get')
	if target == unsafe { nil } { return unsafe { nil } }
	key := py_string(name)
	result := gap_call(target, [key, default_value])
	drop(key)
	drop(target)
	return result
}

fn gap_equal_result(value voidptr, text string) voidptr {
	target := py_string(text)
	result := C.PyObject_RichCompare(value, target, C.Py_EQ)
	drop(target)
	return result
}

fn gap_truth_result(result voidptr) i32 {
	if result == unsafe { nil } { return -1 }
	truth := C.PyObject_IsTrue(result)
	drop(result)
	return truth
}

fn gap_text_equal(value voidptr, text string) bool {
	return gap_truth_result(gap_equal_result(value, text)) > 0
}

fn gap_is_none(value voidptr) bool {
	none_value := py_none()
	result := value == none_value
	drop(none_value)
	return result
}

fn gap_none_get(value voidptr, name string) voidptr {
	none_value := py_none()
	result := gap_get(value, name, none_value)
	drop(none_value)
	return result
}

fn gap_empty_get(value voidptr, name string, dictionary bool) voidptr {
	empty := if dictionary { C.PyDict_New() } else { C.PyList_New(0) }
	result := gap_get(value, name, empty)
	drop(empty)
	return result
}

fn (s &GapLibrary) sdk_get(name string) voidptr {
	value := unsafe { C.PyDict_GetItemString(s.sdk, name.str) }
	if value != unsafe { nil } { return own(value) }
	builtins := unsafe { C.PyDict_GetItemString(s.sdk, c'__builtins__') }
	dictionary := if C.PyDict_Check(builtins) != 0 {
		builtins
	} else {
		C.PyModule_GetDict(builtins)
	}
	value2 := unsafe { C.PyDict_GetItemString(dictionary, name.str) }
	if value2 != unsafe { nil } { return own(value2) }
	message := py_string("name '" + name + "' is not defined")
	C.PyErr_SetObject(unsafe { voidptr(C.PyExc_NameError) }, message)
	drop(message)
	return unsafe { nil }
}

fn (s &GapLibrary) retain(value voidptr) voidptr {
	zero := C.PyLong_FromLongLong(0)
	number := gap_get(s.resources, 'next_id', zero)
	drop(zero)
	if number == unsafe { nil } { return unsafe { nil } }
	one := C.PyLong_FromLongLong(1)
	updated := C.PyNumber_Add(number, one)
	drop(one)
	drop(number)
	if updated == unsafe { nil } { return unsafe { nil } }
	gap_set(s.resources, 'next_id', updated)
	drop(updated)
	if C.PyErr_Occurred() != unsafe { nil } { return unsafe { nil } }
	target := s.sdk_get('str')
	if target == unsafe { nil } { return unsafe { nil } }
	actual := gap_item(s.resources, 'next_id')
	if actual == unsafe { nil } {
		drop(target)
		return unsafe { nil }
	}
	ident := gap_call(target, [actual])
	drop(actual)
	drop(target)
	if ident == unsafe { nil } { return unsafe { nil } }
	C.PyObject_SetItem(s.resources, ident, value)
	if C.PyErr_Occurred() != unsafe { nil } {
		drop(ident)
		return unsafe { nil }
	}
	return ident
}

fn gap_index(value voidptr, index i64) voidptr {
	key := C.PyLong_FromLongLong(index)
	result := C.PyObject_GetItem(value, key)
	drop(key)
	return result
}

fn (s &GapLibrary) getattr(owner voidptr, name voidptr) voidptr {
	target := s.sdk_get('getattr')
	if target == unsafe { nil } { return unsafe { nil } }
	result := gap_call(target, [owner, name])
	drop(target)
	return result
}

fn (s &GapLibrary) resolve(name voidptr) voidptr {
	dot := py_string('.')
	parts := gap_method(name, 'split', [dot])
	drop(dot)
	if parts == unsafe { nil } { return unsafe { nil } }
	mut result := voidptr(0)
	mut previous := voidptr(0)
	defer {
		s.pin_failed_scope(['name', 'parts', 'value', 'part'], [name, parts, result, previous])
		drop(parts)
		drop(result)
		drop(previous)
	}
	len_target := s.sdk_get('len')
	if len_target == unsafe { nil } { return unsafe { nil } }
	length := gap_call(len_target, [parts])
	drop(len_target)
	if length == unsafe { nil } { return unsafe { nil } }
	two := C.PyLong_FromLongLong(2)
	compared := C.PyObject_RichCompare(length, two, C.Py_EQ)
	drop(length)
	drop(two)
	sized := gap_truth_result(compared)
	if sized < 0 { return unsafe { nil } }
	mut special := false
	if sized > 0 {
		first := gap_index(parts, 0)
		if first == unsafe { nil } { return unsafe { nil } }
		comparison := gap_equal_result(first, 'builtins')
		drop(first)
		special = gap_truth_result(comparison) > 0
		if C.PyErr_Occurred() != unsafe { nil } { return unsafe { nil } }
	}
	if special {
		target := gap_attr(s.namespace, 'get')
		if target == unsafe { nil } { return unsafe { nil } }
		key := gap_index(parts, 1)
		if key == unsafe { nil } {
			drop(target)
			return unsafe { nil }
		}
		getter := s.sdk_get('getattr')
		if getter == unsafe { nil } {
			drop(key)
			drop(target)
			return unsafe { nil }
		}
		builtins := s.sdk_get('builtins')
		if builtins == unsafe { nil } {
			drop(getter)
			drop(key)
			drop(target)
			return unsafe { nil }
		}
		fallback_name := gap_index(parts, 1)
		if fallback_name == unsafe { nil } {
			drop(builtins)
			drop(getter)
			drop(key)
			drop(target)
			return unsafe { nil }
		}
		fallback := gap_call(getter, [builtins, fallback_name])
		drop(fallback_name)
		drop(getter)
		drop(builtins)
		if fallback == unsafe { nil } {
			drop(key)
			drop(target)
			return unsafe { nil }
		}
		special_result := gap_call(target, [key, fallback])
		drop(key)
		drop(fallback)
		drop(target)
		return special_result
	}
	builtins := s.sdk_get('builtins')
	if builtins == unsafe { nil } { return unsafe { nil } }
	operator := s.sdk_get('operator')
	if operator == unsafe { nil } {
		drop(builtins)
		return unsafe { nil }
	}
	dictionary := C.PyDict_New()
	unsafe {
		C.PyDict_SetItemString(dictionary, c'builtins', builtins)
		C.PyDict_SetItemString(dictionary, c'operator', operator)
	}
	drop(builtins)
	drop(operator)
	chooser := gap_attr(dictionary, 'get')
	drop(dictionary)
	if chooser == unsafe { nil } { return unsafe { nil } }
	first := gap_index(parts, 0)
	if first == unsafe { nil } {
		drop(chooser)
		return unsafe { nil }
	}
	target := gap_attr(s.namespace, 'get')
	if target == unsafe { nil } {
		drop(first)
		drop(chooser)
		return unsafe { nil }
	}
	fallback_name := gap_index(parts, 0)
	if fallback_name == unsafe { nil } {
		drop(target)
		drop(first)
		drop(chooser)
		return unsafe { nil }
	}
	fallback := gap_call(target, [fallback_name])
	drop(fallback_name)
	drop(target)
	if fallback == unsafe { nil } {
		drop(first)
		drop(chooser)
		return unsafe { nil }
	}
	result = gap_call(chooser, [first, fallback])
	drop(first)
	drop(fallback)
	drop(chooser)
	if result == unsafe { nil } { return unsafe { nil } }
	start := C.PyLong_FromLongLong(1)
	slice := C.PySlice_New(start, unsafe { nil }, unsafe { nil })
	drop(start)
	tail := C.PyObject_GetItem(parts, slice)
	drop(slice)
	if tail == unsafe { nil } { return unsafe { nil } }
	items := C.PyObject_GetIter(tail)
	drop(tail)
	if items == unsafe { nil } { return unsafe { nil } }
	for {
		part := C.PyIter_Next(items)
		if part == unsafe { nil } { break }
		drop(previous)
		previous = part
		next := s.getattr(result, part)
		if next == unsafe { nil } { break }
		drop(result)
		result = next
	}
	drop(items)
	if C.PyErr_Occurred() != unsafe { nil } { return unsafe { nil } }
	return own(result)
}

fn (s &GapLibrary) pin_failed_scope(names []string, values []voidptr) {
	if C.PyErr_Occurred() == unsafe { nil } { return }
	pending := caught()
	scope := C.PyDict_New()
	for i, name in names {
		if values[i] != unsafe { nil } {
			unsafe { C.PyDict_SetItemString(scope, name.str, values[i]) }
		}
	}
	// Unwind an inner traceback frame before the caller's fast locals.
	C.PyList_Insert(s.error_pins, 0, scope)
	drop(scope)
	pending.restore()
	pending.discard()
}

fn (s &GapLibrary) mapped_list(values voidptr) voidptr {
	items := C.PyObject_GetIter(values)
	drop(values)
	if items == unsafe { nil } { return unsafe { nil } }
	list := C.PyList_New(0)
	mut previous := voidptr(0)
	for {
		item := C.PyIter_Next(items)
		if item == unsafe { nil } { break }
		drop(previous)
		previous = item
		value := gap_call(s.argument, [item])
		if value == unsafe { nil } { break }
		C.PyList_Append(list, value)
		drop(value)
		if C.PyErr_Occurred() != unsafe { nil } { break }
	}
	s.pin_failed_scope(['.0', 'value'], [items, previous])
	drop(items)
	drop(previous)
	if C.PyErr_Occurred() != unsafe { nil } {
		drop(list)
		return unsafe { nil }
	}
	return list
}

fn (s &GapLibrary) mapped_kwargs(values voidptr) voidptr {
	iterable := gap_method(values, 'items', [])
	drop(values)
	if iterable == unsafe { nil } { return unsafe { nil } }
	items := C.PyObject_GetIter(iterable)
	drop(iterable)
	if items == unsafe { nil } { return unsafe { nil } }
	dict := C.PyDict_New()
	mut key := voidptr(0)
	mut item := voidptr(0)
	for {
		container := C.PyIter_Next(items)
		if container == unsafe { nil } { break }
		pair := gap_call(s.pair, [container])
		drop(container)
		if pair == unsafe { nil } { break }
		next_key := own(C.PyTuple_GetItem(pair, 0))
		next_item := own(C.PyTuple_GetItem(pair, 1))
		drop(pair)
		drop(key)
		drop(item)
		key = next_key
		item = next_item
		value := gap_call(s.argument, [item])
		if value == unsafe { nil } { break }
		C.PyDict_SetItem(dict, key, value)
		drop(value)
		if C.PyErr_Occurred() != unsafe { nil } { break }
	}
	s.pin_failed_scope(['.0', 'key', 'value'], [items, key, item])
	drop(items)
	drop(key)
	drop(item)
	if C.PyErr_Occurred() != unsafe { nil } {
		drop(dict)
		return unsafe { nil }
	}
	return dict
}

fn (s &GapLibrary) function(row voidptr) voidptr {
	owner_key := py_string('owner')
	has_owner_value := C.PySequence_Contains(row, owner_key)
	drop(owner_key)
	if has_owner_value < 0 { return unsafe { nil } }
	has_owner := has_owner_value != 0
	mut target := voidptr(0)
	if has_owner {
		getter := s.sdk_get('getattr')
		if getter == unsafe { nil } { return unsafe { nil } }
		ident := gap_item(row, 'owner')
		if ident == unsafe { nil } {
			drop(getter)
			return unsafe { nil }
		}
		owner := C.PyObject_GetItem(s.resources, ident)
		drop(ident)
		if owner == unsafe { nil } {
			drop(getter)
			return unsafe { nil }
		}
		method := gap_item(row, 'method')
		if method == unsafe { nil } {
			drop(owner)
			drop(getter)
			return unsafe { nil }
		}
		target = gap_call(getter, [owner, method])
		drop(method)
		drop(owner)
		drop(getter)
	} else {
		name := gap_item(row, 'name')
		if name == unsafe { nil } { return unsafe { nil } }
		target = s.resolve(name)
		drop(name)
	}
	if target == unsafe { nil } { return unsafe { nil } }
	mut value := voidptr(0)
	mut mode := voidptr(0)
	defer {
		s.pin_failed_scope(['target', 'value', 'mode'], [target, value, mode])
		drop(target)
		drop(value)
		drop(mode)
	}
	call_flag := gap_none_get(row, 'call')
	if call_flag == unsafe { nil } { return unsafe { nil } }
	mut should_call := C.PyObject_IsTrue(call_flag)
	drop(call_flag)
	if should_call < 0 { return unsafe { nil } }
	if should_call == 0 {
		checker := s.sdk_get('callable')
		if checker == unsafe { nil } { return unsafe { nil } }
		checked := gap_call(checker, [target])
		drop(checker)
		if checked == unsafe { nil } { return unsafe { nil } }
		should_call = C.PyObject_IsTrue(checked)
		drop(checked)
		if should_call < 0 { return unsafe { nil } }
	}
	if should_call != 0 {
		values := gap_empty_get(row, 'args', false)
		if values == unsafe { nil } { return unsafe { nil } }
		list := s.mapped_list(values)
		if list == unsafe { nil } { return unsafe { nil } }
		args := C.PyList_AsTuple(list)
		drop(list)
		if args == unsafe { nil } { return unsafe { nil } }
		values2 := gap_empty_get(row, 'kwargs', true)
		if values2 == unsafe { nil } {
			drop(args)
			return unsafe { nil }
		}
		kwargs := s.mapped_kwargs(values2)
		if kwargs == unsafe { nil } {
			drop(args)
			return unsafe { nil }
		}
		value = C.PyObject_Call(target, args, kwargs)
		drop(kwargs)
		drop(args)
	} else {
		value = own(target)
	}
	if value == unsafe { nil } { return unsafe { nil } }
	method := gap_none_get(row, 'method')
	if method == unsafe { nil } { return unsafe { nil } }
	compared_method := gap_equal_result(method, '__enter__')
	drop(method)
	enters := gap_truth_result(compared_method) > 0
	if C.PyErr_Occurred() != unsafe { nil } { return unsafe { nil } }
	if enters {
		ident := gap_item(row, 'owner')
		if ident == unsafe { nil } { return unsafe { nil } }
		result := gap_call(s.registration, [ident])
		drop(ident)
		if result == unsafe { nil } { return unsafe { nil } }
		drop(result)
	}
	default_mode := py_string('value')
	mode = gap_get(row, 'result', default_mode)
	drop(default_mode)
	if mode == unsafe { nil } { return unsafe { nil } }
	retained := gap_text_equal(mode, 'owner')
	if C.PyErr_Occurred() != unsafe { nil } { return unsafe { nil } }
	if retained {
		ident := s.retain(value)
		if enters && ident != unsafe { nil } {
			original_ident := gap_item(row, 'owner')
			if original_ident == unsafe { nil } {
				drop(ident)
				return unsafe { nil }
			}
			entry := gap_call(s.registration, [original_ident, ident])
			drop(original_ident)
			if entry == unsafe { nil } {
				drop(ident)
				return unsafe { nil }
			}
			drop(entry)
		}
		return ident
	}
	path_result := gap_text_equal(mode, 'path')
	if C.PyErr_Occurred() != unsafe { nil } { return unsafe { nil } }
	if path_result {
		factory := s.sdk_get('str')
		result := gap_call(factory, [value])
		drop(factory)
		return result
	}
	bytes_result := gap_text_equal(mode, 'bytes')
	if C.PyErr_Occurred() != unsafe { nil } { return unsafe { nil } }
	if bytes_result { return gap_method(value, 'hex', []) }
	return own(value)
}

fn (s &GapLibrary) type_is(value voidptr, name string) bool {
	target := s.sdk_get('type')
	kind := gap_call(target, [value])
	drop(target)
	if kind == unsafe { nil } { return false }
	expected := s.sdk_get(name)
	same := kind == expected
	drop(kind)
	drop(expected)
	return same
}

fn (s &GapLibrary) wait_once(row voidptr) voidptr {
	pid := gap_item(s.resources, 'pid')
	if pid == unsafe { nil } { return unsafe { nil } }
	mut api := voidptr(0)
	mut status := voidptr(0)
	defer {
		s.pin_failed_scope(['pid', 'api', 'status'], [pid, api, status])
		drop(pid)
		drop(api)
		drop(status)
	}
	api = gap_item(s.namespace, 'os')
	if api == unsafe { nil } { return unsafe { nil } }
	target := gap_attr(api, 'waitpid')
	if target == unsafe { nil } { return unsafe { nil } }
	flag := gap_attr(api, 'WNOHANG')
	if flag == unsafe { nil } {
		drop(target)
		return unsafe { nil }
	}
	status = gap_call(target, [pid, flag])
	drop(flag)
	drop(target)
	if status == unsafe { nil } { return unsafe { nil } }
	if s.type_is(status, 'tuple') {
		len_target := s.sdk_get('len')
		length := gap_call(len_target, [status])
		drop(len_target)
		if length == unsafe { nil } { return unsafe { nil } }
		two := C.PyLong_FromLongLong(2)
		compared_length := C.PyObject_RichCompare(length, two, C.Py_EQ)
		drop(length)
		drop(two)
		exact_length := gap_truth_result(compared_length)
		if exact_length < 0 { return unsafe { nil } }
		if exact_length > 0 {
			zero := C.PyLong_FromLongLong(0)
			first := C.PyObject_GetItem(status, zero)
			drop(zero)
			if first == unsafe { nil } { return unsafe { nil } }
			exact_first := s.type_is(first, 'int')
			drop(first)
			if C.PyErr_Occurred() != unsafe { nil } { return unsafe { nil } }
			if exact_first && s.type_is(pid, 'int') {
				zero2 := C.PyLong_FromLongLong(0)
				first2 := C.PyObject_GetItem(status, zero2)
				drop(zero2)
				if first2 == unsafe { nil } { return unsafe { nil } }
				compared_pid := C.PyObject_RichCompare(first2, pid, C.Py_EQ)
				drop(first2)
				matched := gap_truth_result(compared_pid)
				if matched < 0 { return unsafe { nil } }
				if matched > 0 {
					yes := C.PyBool_FromLong(1)
					gap_set(s.resources, 'reaped', yes)
					drop(yes)
				}
			}
		}
	}
	if C.PyErr_Occurred() != unsafe { nil } { return unsafe { nil } }
	mode := gap_none_get(row, 'result')
	if mode == unsafe { nil } { return unsafe { nil } }
	compared_mode := gap_equal_result(mode, 'owner')
	drop(mode)
	retained := gap_truth_result(compared_mode) > 0
	if C.PyErr_Occurred() != unsafe { nil } { return unsafe { nil } }
	return if retained { s.retain(status) } else { own(status) }
}

fn (s &GapLibrary) is_instance(value voidptr, name string) i32 {
	checker := s.sdk_get('isinstance')
	if checker == unsafe { nil } { return -1 }
	class := s.sdk_get(name)
	if class == unsafe { nil } {
		drop(checker)
		return -1
	}
	checked := gap_call(checker, [value, class])
	drop(class)
	drop(checker)
	if checked == unsafe { nil } { return -1 }
	result := C.PyObject_IsTrue(checked)
	drop(checked)
	return result
}

fn (s &GapLibrary) restore(value voidptr) voidptr {
	defer { s.pin_failed_scope(['value'], [value]) }
	// Match the wrapper's isinstance semantics, including caller replacement
	// of the global classes and factories used by the recursive result policy.
	is_list := s.is_instance(value, 'list')
	if is_list < 0 { return unsafe { nil } }
	if is_list != 0 {
		items := C.PyObject_GetIter(value)
		if items == unsafe { nil } { return unsafe { nil } }
		result := C.PyList_New(0)
		mut previous := voidptr(0)
		for {
			item := C.PyIter_Next(items)
			if item == unsafe { nil } { break }
			drop(previous)
			previous = item
			next := s.restore(item)
			if next == unsafe { nil } { break }
			C.PyList_Append(result, next)
			drop(next)
			if C.PyErr_Occurred() != unsafe { nil } { break }
		}
		s.pin_failed_scope(['.0', 'item'], [items, previous])
		drop(items)
		drop(previous)
		if C.PyErr_Occurred() != unsafe { nil } {
			drop(result)
			return unsafe { nil }
		}
		return result
	}
	is_dict := s.is_instance(value, 'dict')
	if is_dict < 0 { return unsafe { nil } }
	if is_dict != 0 {
		factory := s.sdk_get('set')
		keys := gap_call(factory, [value])
		drop(factory)
		if keys == unsafe { nil } { return unsafe { nil } }
		expected := C.PySet_New(unsafe { nil })
		key := py_string('owner_result')
		C.PySet_Add(expected, key)
		compared_keys := C.PyObject_RichCompare(keys, expected, C.Py_EQ)
		drop(keys)
		drop(expected)
		same := gap_truth_result(compared_keys)
		if same < 0 {
			drop(key)
			return unsafe { nil }
		}
		if same > 0 {
			ident := C.PyObject_GetItem(value, key)
			drop(key)
			if ident == unsafe { nil } { return unsafe { nil } }
			result := C.PyObject_GetItem(s.resources, ident)
			drop(ident)
			return result
		}
		drop(key)
	}
	return own(value)
}

fn (s &GapLibrary) primitive(method string, row voidptr) voidptr {
	match method {
		'function' { return s.function(row) }
		'wait_once' { return s.wait_once(row) }
		'release_since' {
			factory := s.sdk_get('set')
			empty := C.PyTuple_New(0)
			kept := gap_get(row, 'keep', empty)
			drop(empty)
			if kept == unsafe { nil } {
				drop(factory)
				return unsafe { nil }
			}
			left := gap_call(factory, [kept])
			drop(kept)
			drop(factory)
			if left == unsafe { nil } { return unsafe { nil } }
			right := gap_method(s.entered, 'keys', [])
			if right == unsafe { nil } {
				drop(left)
				return unsafe { nil }
			}
			keep := C.PyNumber_Or(left, right)
			drop(left)
			drop(right)
			if keep == unsafe { nil } { return unsafe { nil } }
			defer { drop(keep) }
			update := gap_attr(keep, 'update')
			if update == unsafe { nil } { return unsafe { nil } }
			ids := gap_call(s.entered_ids, [])
			if ids == unsafe { nil } {
				drop(update)
				return unsafe { nil }
			}
			updated := gap_call(update, [ids])
			drop(ids)
			drop(update)
			if updated == unsafe { nil } { return unsafe { nil } }
			drop(updated)
			tuple_factory := s.sdk_get('tuple')
			names := gap_call(tuple_factory, [s.resources])
			drop(tuple_factory)
			if names == unsafe { nil } { return unsafe { nil } }
			items := C.PyObject_GetIter(names)
			drop(names)
			if items == unsafe { nil } { return unsafe { nil } }
			mut previous := voidptr(0)
			for {
				ident := C.PyIter_Next(items)
				if ident == unsafe { nil } { break }
				drop(previous)
				previous = ident
				checker := s.sdk_get('isinstance')
				str_class := s.sdk_get('str')
				checked := gap_call(checker, [ident, str_class])
				drop(str_class)
				drop(checker)
				if checked == unsafe { nil } { break }
				is_text := C.PyObject_IsTrue(checked)
				drop(checked)
				if is_text < 0 { break }
				if is_text == 0 { continue }
				decimal := gap_method(ident, 'isdecimal', [])
				if decimal == unsafe { nil } { break }
				is_decimal := C.PyObject_IsTrue(decimal)
				drop(decimal)
				if is_decimal < 0 { break }
				if is_decimal == 0 { continue }
				int_factory := s.sdk_get('int')
				number := gap_call(int_factory, [ident])
				drop(int_factory)
				if number == unsafe { nil } { break }
				checkpoint := gap_item(row, 'checkpoint')
				if checkpoint == unsafe { nil } {
					drop(number)
					break
				}
				compared := C.PyObject_RichCompare(number, checkpoint, C.Py_GE)
				drop(number)
				drop(checkpoint)
				comparison := gap_truth_result(compared)
				if comparison < 0 { break }
				if comparison == 0 { continue }
				retained := C.PySequence_Contains(keep, ident)
				if retained < 0 { break }
				if retained != 0 { continue }
				result := gap_method(s.resources, 'pop', [ident])
				if result == unsafe { nil } { break }
				drop(result)
			}
			s.pin_failed_scope(['ident', 'keep'], [previous, keep])
			drop(items)
			drop(previous)
			return if C.PyErr_Occurred() == unsafe { nil } { py_none() } else { unsafe { nil } }
		}
		'boot' {
			policy_id := gap_item(row, 'policy')
			if policy_id == unsafe { nil } { return unsafe { nil } }
			policy := C.PyObject_GetItem(s.resources, policy_id)
			drop(policy_id)
			if policy == unsafe { nil } { return unsafe { nil } }
			pair := gap_call(s.pair, [policy])
			drop(policy)
			if pair == unsafe { nil } { return unsafe { nil } }
			expected := own(C.PyTuple_GetItem(pair, 0))
			failures := own(C.PyTuple_GetItem(pair, 1))
			drop(pair)
			defer {
				s.pin_failed_scope(['expected', 'failures'], [expected, failures])
				drop(expected)
				drop(failures)
			}
			target := gap_item(s.namespace, 'boot')
			if target == unsafe { nil } { return unsafe { nil } }
			command := gap_item(row, 'command')
			if command == unsafe { nil } {
				drop(target)
				return unsafe { nil }
			}
			env := gap_item(row, 'env')
			if env == unsafe { nil } {
				drop(command)
				drop(target)
				return unsafe { nil }
			}
			path_factory := s.sdk_get('Path')
			state_text := gap_item(row, 'state')
			if state_text == unsafe { nil } {
				drop(path_factory)
				drop(env)
				drop(command)
				drop(target)
				return unsafe { nil }
			}
			state := gap_call(path_factory, [state_text])
			drop(state_text)
			drop(path_factory)
			if state == unsafe { nil } {
				drop(env)
				drop(command)
				drop(target)
				return unsafe { nil }
			}
			timeout := gap_item(s.resources, 'timeout')
			if timeout == unsafe { nil } {
				drop(state)
				drop(env)
				drop(command)
				drop(target)
				return unsafe { nil }
			}
			result := gap_call(target, [command, env, state, expected,
				failures, timeout])
			drop(timeout)
			drop(state)
			drop(env)
			drop(command)
			drop(target)
			return result
		}
		'restore' { return s.restore(row) }
		'main_policy' {
			options := gap_item(s.resources, 'options')
			if options == unsafe { nil } { return unsafe { nil } }
			mut expected := voidptr(0)
			mut failures := voidptr(0)
			defer {
				s.pin_failed_scope(['options', 'expected', 'failures'], [options, expected, failures])
				drop(options)
				drop(expected)
				drop(failures)
			}
			target := gap_item(s.namespace, 'verdict_policy')
			if target == unsafe { nil } { return unsafe { nil } }
			expect := gap_attr(options, 'expect')
			if expect == unsafe { nil } {
				drop(target)
				return unsafe { nil }
			}
			fail := gap_attr(options, 'fail')
			if fail == unsafe { nil } {
				drop(expect)
				drop(target)
				return unsafe { nil }
			}
			panic := gap_attr(options, 'expect_panic')
			if panic == unsafe { nil } {
				drop(fail)
				drop(expect)
				drop(target)
				return unsafe { nil }
			}
			result := gap_call(target, [expect, fail, panic])
			drop(panic)
			drop(fail)
			drop(expect)
			drop(target)
			if result == unsafe { nil } { return unsafe { nil } }
			pair := gap_call(s.pair, [result])
			drop(result)
			if pair == unsafe { nil } { return unsafe { nil } }
			expected = own(C.PyTuple_GetItem(pair, 0))
			failures = own(C.PyTuple_GetItem(pair, 1))
			ident := s.retain(pair)
			drop(pair)
			return ident
		}
		'raise_builtin' {
			builtins := s.sdk_get('builtins')
			kind_name := gap_item(row, 'kind')
			if kind_name == unsafe { nil } {
				drop(builtins)
				return unsafe { nil }
			}
			target := C.PyObject_GetAttr(builtins, kind_name)
			drop(kind_name)
			drop(builtins)
			if target == unsafe { nil } { return unsafe { nil } }
			expression := gap_item(row, 'value')
			if expression == unsafe { nil } {
				drop(target)
				return unsafe { nil }
			}
			value := gap_call(s.argument, [expression])
			drop(expression)
			if value == unsafe { nil } {
				drop(target)
				return unsafe { nil }
			}
			error := gap_call(target, [value])
			drop(value)
			drop(target)
			if error == unsafe { nil } { return unsafe { nil } }
			if C.PyExceptionInstance_Check(error) == 0 {
				text := py_string('exceptions must derive from BaseException')
				C.PyErr_SetObject(unsafe { voidptr(C.PyExc_TypeError) }, text)
				drop(text)
			} else {
				C.PyErr_SetObject(C.Py_TYPE(error), error)
			}
			drop(error)
			return unsafe { nil }
		}
		'drain' {
			target := gap_item(s.resources, 'drain')
			if target == unsafe { nil } { return unsafe { nil } }
			result := gap_call(target, [])
			drop(target)
			return result
		}
		'stop' {
			target := gap_item(s.namespace, 'stop')
			if target == unsafe { nil } { return unsafe { nil } }
			pid := gap_item(s.resources, 'pid')
			if pid == unsafe { nil } {
				drop(target)
				return unsafe { nil }
			}
			master := gap_item(s.resources, 'master')
			if master == unsafe { nil } {
				drop(pid)
				drop(target)
				return unsafe { nil }
			}
			state := gap_item(s.resources, 'state')
			if state == unsafe { nil } {
				drop(master)
				drop(pid)
				drop(target)
				return unsafe { nil }
			}
			callback := gap_call(s.stop_drain, [])
			if callback == unsafe { nil } {
				drop(state)
				drop(master)
				drop(pid)
				drop(target)
				return unsafe { nil }
			}
			result := gap_call(target, [pid, master, state, callback])
			drop(callback)
			drop(state)
			drop(master)
			drop(pid)
			drop(target)
			return result
		}
		'list_new' {
			value := C.PyList_New(0)
			ident := s.retain(value)
			drop(value)
			return ident
		}
		'unpack' {
			ident := gap_item(row, 'owner')
			if ident == unsafe { nil } { return unsafe { nil } }
			value := C.PyObject_GetItem(s.resources, ident)
			drop(ident)
			if value == unsafe { nil } { return unsafe { nil } }
			list := C.PySequence_List(value)
			drop(value)
			if list == unsafe { nil } { return unsafe { nil } }
			result := s.retain(list)
			drop(list)
			return result
		}
		'next' {
			ident := gap_item(row, 'id')
			if ident == unsafe { nil } { return unsafe { nil } }
			iterator := C.PyObject_GetItem(s.resources, ident)
			drop(ident)
			if iterator == unsafe { nil } { return unsafe { nil } }
			target := s.sdk_get('next')
			if target == unsafe { nil } {
				drop(iterator)
				return unsafe { nil }
			}
			item := gap_call(target, [iterator])
			drop(iterator)
			drop(target)
			if item == unsafe { nil } {
				failure := caught()
				class := s.sdk_get('StopIteration')
				if class == unsafe { nil } {
					failure.discard()
					return unsafe { nil }
				}
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
					message := py_string('catching classes that do not inherit from BaseException is not allowed')
					C.PyErr_SetObject(unsafe { voidptr(C.PyExc_TypeError) }, message)
					drop(message)
					drop(class)
					failure.discard()
					return unsafe { nil }
				}
				matches := C.PyErr_GivenExceptionMatches(failure.kind, class) != 0
				drop(class)
				if !matches { failure.restore() }
				failure.discard()
				if !matches { return unsafe { nil } }
			}
			result := C.PyDict_New()
			done := C.PyBool_FromLong(if item == unsafe { nil } { 1 } else { 0 })
			unsafe { C.PyDict_SetItemString(result, c'done', done) }
			drop(done)
			if item != unsafe { nil } {
				ident2 := s.retain(item)
				drop(item)
				if ident2 == unsafe { nil } {
					drop(result)
					return unsafe { nil }
				}
				unsafe { C.PyDict_SetItemString(result, c'owner', ident2) }
				drop(ident2)
			}
			return result
		}
		'release' {
			ids := gap_item(row, 'ids')
			if ids == unsafe { nil } { return unsafe { nil } }
			items := C.PyObject_GetIter(ids)
			drop(ids)
			if items == unsafe { nil } { return unsafe { nil } }
			mut previous := voidptr(0)
			for {
				ident := C.PyIter_Next(items)
				if ident == unsafe { nil } { break }
				drop(previous)
				previous = ident
				none_value := py_none()
				result := gap_method(s.resources, 'pop', [ident, none_value])
				drop(none_value)
				if result == unsafe { nil } { break }
				drop(result)
			}
			s.pin_failed_scope(['ident'], [previous])
			drop(items)
			drop(previous)
			return if C.PyErr_Occurred() == unsafe { nil } { py_none() } else { unsafe { nil } }
		}
		'checkpoint' {
			zero := C.PyLong_FromLongLong(0)
			number := gap_get(s.resources, 'next_id', zero)
			drop(zero)
			if number == unsafe { nil } { return unsafe { nil } }
			one := C.PyLong_FromLongLong(1)
			result := C.PyNumber_Add(number, one)
			drop(number)
			drop(one)
			return result
		}
		'closed', 'reaped' {
			yes := C.PyBool_FromLong(1)
			gap_set(s.resources, method, yes)
			drop(yes)
			return if C.PyErr_Occurred() == unsafe { nil } { py_none() } else { unsafe { nil } }
		}
		'close_fd' {
			master := gap_item(s.resources, 'master')
			if master == unsafe { nil } { return unsafe { nil } }
			defer {
				s.pin_failed_scope(['master'], [master])
				drop(master)
			}
			yes := C.PyBool_FromLong(1)
			gap_set(s.resources, 'closed', yes)
			drop(yes)
			if C.PyErr_Occurred() != unsafe { nil } {
				return unsafe { nil }
			}
			api := gap_item(s.namespace, 'os')
			if api == unsafe { nil } {
				return unsafe { nil }
			}
			target := gap_attr(api, 'close')
			drop(api)
			if target == unsafe { nil } { return unsafe { nil } }
			result := gap_call(target, [master])
			drop(target)
			return result
		}
		else {
			kind := s.sdk_get('RuntimeError')
			message := py_string('unknown kernel-gap native primitive: ' + method)
			C.PyErr_SetObject(kind, message)
			drop(message)
			drop(kind)
			return unsafe { nil }
		}
	}
}

pub fn gap_library_entry(operation &char, namespace voidptr, arguments voidptr, syntax voidptr) voidptr {
	op := unsafe { operation.vstring() }
	if op == 'begin' {
		key := gap_library_serial
		gap_library_serial++
		gap_libraries[key] = &GapLibrary{
			namespace:    own(namespace)
			resources:    own(C.PyTuple_GetItem(arguments, 0))
			sdk:          own(C.PyTuple_GetItem(arguments, 1))
			argument:     own(C.PyTuple_GetItem(arguments, 2))
			registration: own(C.PyTuple_GetItem(arguments, 3))
			entered:      own(C.PyTuple_GetItem(arguments, 4))
			stop_drain:   own(C.PyTuple_GetItem(arguments, 5))
			entered_ids:  own(C.PyTuple_GetItem(arguments, 6))
			error_pins:   C.PyList_New(0)
			pair:         own(unsafe { C.PyDict_GetItemString(syntax, c'pair') })
		}
		return C.PyLong_FromUnsignedLongLong(key)
	}
	key := C.PyLong_AsUnsignedLongLong(C.PyTuple_GetItem(arguments, 0))
	mut session := gap_libraries[key] or {
		value := C.PyLong_FromUnsignedLongLong(key)
		C.PyErr_SetObject(unsafe { voidptr(C.PyExc_KeyError) }, value)
		drop(value)
		return unsafe { nil }
	}
	if op == 'error_pins' {
		result := session.error_pins
		session.error_pins = C.PyList_New(0)
		return result
	}
	if op == 'close' {
		gap_libraries.delete(key)
		drop(session.namespace)
		drop(session.resources)
		drop(session.sdk)
		drop(session.argument)
		drop(session.registration)
		drop(session.entered)
		drop(session.stop_drain)
		drop(session.entered_ids)
		drop(session.error_pins)
		drop(session.pair)
		return py_none()
	}
	result := session.primitive(op, C.PyTuple_GetItem(arguments, 1))
	if C.PyErr_Occurred() != unsafe { nil } {
		drop(result)
		return unsafe { nil }
	}
	return result
}
