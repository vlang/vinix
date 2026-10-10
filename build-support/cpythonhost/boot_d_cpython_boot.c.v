// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

fn C.PyObject_GetItem(voidptr, voidptr) voidptr
fn C.PyObject_SetItem(voidptr, voidptr, voidptr) i32
fn C.PyObject_DelItem(voidptr, voidptr) i32
fn C.PySequence_Contains(voidptr, voidptr) i32
fn C.PySequence_Tuple(voidptr) voidptr
fn C.PyList_Append(voidptr, voidptr) i32
fn C.PyList_Insert(voidptr, isize, voidptr) i32
fn C.PyNumber_Add(voidptr, voidptr) voidptr
fn C.PyLong_CheckExact(voidptr) i32
fn C.PyObject_RichCompareBool(voidptr, voidptr, i32) i32
fn C.PyObject_GetAttr(voidptr, voidptr) voidptr
fn C.PyErr_NoMemory() voidptr
fn C.GC_thread_is_registered() i32
fn C.GC_allow_register_threads()
fn C.GC_get_stack_base(voidptr) i32
fn C.GC_register_my_thread(voidptr) i32
fn C.GC_unregister_my_thread() i32

fn C.PyEval_GetBuiltins() voidptr
fn C.PyUnicode_InternFromString(&char) voidptr

// Literal operands have the lifetime of the loaded implementation, matching
// the constants held by the original Python function objects.
__global boot_literals = map[string]voidptr{}

fn boot_literal(value string) voidptr {
	if result := boot_literals[value] { return own(result) }
	result := unsafe { C.PyUnicode_InternFromString(value.str) }
	if result != unsafe { nil } { boot_literals[value] = own(result) }
	return result
}

// These values are borrowed for this synchronous PyDLL entry. Python
// callbacks keep the current handled state; pending failures remain pending.
struct BootContext {
    namespace voidptr
    builtins voidptr
    pins voidptr
}

// The binding frame owns this list on failure. Its dictionaries preserve the
// original named locals, without adding fields or replaying the actual error.
// Python lists destroy their entries in reverse: an outer scope is prepended
// so that the inner traceback scope retires first.
fn boot_pin(c &BootContext, names []string, values []voidptr) {
	if !pending_error() { return }
	mut kind := voidptr(0)
	mut error_ := voidptr(0)
	mut traceback := voidptr(0)
	C.PyErr_Fetch(&kind, &error_, &traceback)
	scope := C.PyDict_New()
	if scope != unsafe { nil } {
		for i, name in names {
			value := values[i]
			if value != unsafe { nil } && unsafe { C.PyDict_SetItemString(scope, name.str, value) } != 0 { break }
		}
		if !pending_error() { C.PyList_Insert(c.pins, 0, scope) }
		drop(scope)
	}
	C.PyErr_Restore(kind, error_, traceback)
}

fn (c &BootContext) resolve(name string) voidptr {
    mut result := unsafe { C.PyDict_GetItemString(c.namespace, name.str) }
    if result == unsafe { nil } {
        result = unsafe { C.PyDict_GetItemString(c.builtins, name.str) }
    }
    if result == unsafe { nil } {
        message := py_string("name '" + name + "' is not defined")
        C.PyErr_SetObject(unsafe { voidptr(C.PyExc_NameError) }, message)
        drop(message)
        return unsafe { nil }
    }
    return own(result)
}

fn boot_tuple(values []voidptr) voidptr {
	result := C.PyTuple_New(values.len)
	for i, value in values { C.PyTuple_SetItem(result, i, own(value)) }
	return result
}

fn boot_call(target voidptr, values []voidptr) voidptr {
	args := boot_tuple(values)
	result := C.PyObject_Call(target, args, unsafe { nil })
	drop(args)
	return result
}

fn boot_method(value voidptr, name string, args []voidptr) voidptr {
	key := boot_literal(name)
	target := C.PyObject_GetAttr(value, key)
	drop(key)
	if target == unsafe { nil } { return target }
	result := boot_call(target, args)
	drop(target)
	return result
}

fn boot_field(value voidptr, name string) voidptr {
	key := boot_literal(name)
	result := C.PyObject_GetItem(value, key)
	drop(key)
	return result
}

fn boot_default(value voidptr, name string, default_ voidptr) voidptr {
	key := boot_literal(name)
	result := boot_method(value, 'get', [key, default_])
	drop(key)
	return result
}

fn boot_has(value voidptr, name string) i32 {
	key := boot_literal(name)
	result := C.PySequence_Contains(value, key)
	drop(key)
	return result
}

fn boot_register(c &BootContext, resources voidptr, value voidptr) voidptr {
	zero := C.PyLong_FromLongLong(0)
	previous := boot_default(resources, 'next_id', zero)
	drop(zero)
	if previous == unsafe { nil } { boot_pin(c, ['resources', 'value'], [resources, value]); return previous }
	one := C.PyLong_FromLongLong(1)
	ident := C.PyNumber_Add(previous, one)
	drop(previous)
	drop(one)
	if ident == unsafe { nil } { boot_pin(c, ['resources', 'value'], [resources, value]); return ident }
	key := boot_literal('next_id')
	status := C.PyObject_SetItem(resources, key, ident)
	drop(key)
	if status != 0
		|| C.PyObject_SetItem(resources, ident, value) != 0 {
		boot_pin(c, ['resources', 'value', 'ident'], [resources, value, ident])
		drop(ident)
		return unsafe { nil }
	}
	return ident
}

fn boot_instance(c &BootContext, value voidptr, classes []voidptr) i32 {
	target := c.resolve('isinstance')
	if target == unsafe { nil } { return -1 }
	class_ := if classes.len == 1 { own(classes[0]) } else { boot_tuple(classes) }
	result := boot_call(target, [value, class_])
	drop(class_)
	drop(target)
	if result == unsafe { nil } { return -1 }
	truth := C.PyObject_IsTrue(result)
	drop(result)
	return truth
}

// Retain recursive traversal in its original Python implementation so the
// interpreter owns recursion limits, cycles, and failed comprehension frames.
fn boot_argument(c &BootContext, kind voidptr, value voidptr, resources voidptr) voidptr {
	mut name := ''
	for candidate in ['object', 'owned', 'attribute', 'path', 'bytes'] {
		text := boot_literal(candidate)
		equal := C.PyObject_RichCompareBool(kind, text, 2)
		drop(text)
		if equal < 0 { return unsafe { nil } }
		if equal != 0 { name = candidate; break }
	}
	match name {
		'object' { return C.PyObject_GetItem(resources, value) }
		'owned' {
			values := boot_field(resources, 'values')
			if values == unsafe { nil } { return values }
			result := C.PyObject_GetItem(values, value)
			drop(values)
			return result
		}
		'attribute' {
			getter := c.resolve('getattr')
			if getter == unsafe { nil } { return getter }
			zero := C.PyLong_FromLongLong(0)
			one := C.PyLong_FromLongLong(1)
			id := C.PyObject_GetItem(value, zero)
			drop(zero)
			if id == unsafe { nil } { drop(one); drop(getter); return id }
			owner := C.PyObject_GetItem(resources, id)
			drop(id)
			if owner == unsafe { nil } { drop(one); drop(getter); return owner }
			attribute := C.PyObject_GetItem(value, one)
			drop(one)
			if attribute == unsafe { nil } { drop(owner); drop(getter); return attribute }
			result := boot_call(getter, [owner, attribute])
			drop(attribute)
			drop(owner)
			drop(getter)
			return result
		}
		'path' {
			factory := c.resolve('Path')
			if factory == unsafe { nil } { return factory }
			result := boot_call(factory, [value])
			drop(factory)
			return result
		}
		'bytes' {
			factory := c.resolve('bytes')
			if factory == unsafe { nil } { return factory }
			result := boot_method(factory, 'fromhex', [value])
			drop(factory)
			return result
		}
		else { return own(value) }
	}
}

fn boot_arguments(c &BootContext, items voidptr, resources voidptr) voidptr {
	result := C.PyList_New(0)
	iterator := C.PyObject_GetIter(items)
	if iterator == unsafe { nil } { drop(result); return iterator }
	pair_helper := c.resolve('_boot_pair')
	mut kind := voidptr(0)
	mut value := voidptr(0)
	for {
		row := C.PyIter_Next(iterator)
		if row == unsafe { nil } { break }
		pair := boot_call(pair_helper, [row])
		drop(row)
		if pair == unsafe { nil } { break }
		new_kind := own(C.PyTuple_GetItem(pair, 0))
		new_value := own(C.PyTuple_GetItem(pair, 1))
		drop(pair)
		drop(kind)
		kind = new_kind
		drop(value)
		value = new_value
		argument := boot_argument(c, kind, value, resources)
		if argument == unsafe { nil } { break }
		status := C.PyList_Append(result, argument)
		drop(argument)
		if status != 0 { break }
	}
	boot_pin(c, ['.0', 'kind', 'value'], [iterator, kind, value])
	drop(kind)
	drop(value)
	drop(iterator)
	drop(pair_helper)
	if pending_error() { drop(result); return unsafe { nil } }
	return result
}

fn boot_options(c &BootContext, row voidptr, resources voidptr) voidptr {
	factory := c.resolve('dict')
	if factory == unsafe { nil } { return factory }
	empty := C.PyDict_New()
	input := boot_default(row, 'options', empty)
	drop(empty)
	if input == unsafe { nil } { drop(factory); return input }
	options := boot_call(factory, [input])
	drop(input)
	drop(factory)
	if options == unsafe { nil } { return options }
	update_name := boot_literal('update')
	update := C.PyObject_GetAttr(options, update_name)
	drop(update_name)
	if update == unsafe { nil } { return options }
	objects_empty := C.PyDict_New()
	objects := boot_default(row, 'keyword_objects', objects_empty)
	drop(objects_empty)
	if objects == unsafe { nil } { drop(update); return options }
	items := boot_method(objects, 'items', [])
	drop(objects)
	if items == unsafe { nil } { drop(update); return options }
	iterator := C.PyObject_GetIter(items)
	drop(items)
	if iterator == unsafe { nil } { drop(update); return options }
	converted := C.PyDict_New()
	pair_helper := c.resolve('_boot_pair')
	mut key := voidptr(0)
	mut id := voidptr(0)
	for {
		entry := C.PyIter_Next(iterator)
		if entry == unsafe { nil } { break }
		pair := boot_call(pair_helper, [entry])
		drop(entry)
		if pair == unsafe { nil } { break }
		new_key := own(C.PyTuple_GetItem(pair, 0))
		new_id := own(C.PyTuple_GetItem(pair, 1))
		drop(pair)
		drop(key)
		key = new_key
		drop(id)
		id = new_id
		value := C.PyObject_GetItem(resources, id)
		if value == unsafe { nil } { break }
		status := C.PyObject_SetItem(converted, key, value)
		drop(value)
		if status != 0 { break }
	}
	boot_pin(c, ['.0', 'key', 'value'], [iterator, key, id])
	drop(key)
	drop(id)
	drop(iterator)
	drop(pair_helper)
	if pending_error() { drop(converted); drop(update); return options }
	updated := boot_call(update, [converted])
	drop(converted)
	drop(update)
	drop(updated)
	return options
}

fn boot_row_arguments(c &BootContext, row voidptr, resources voidptr, name string) voidptr {
	empty := C.PyList_New(0)
	items := boot_default(row, name, empty)
	drop(empty)
	if items == unsafe { nil } { return items }
	result := boot_arguments(c, items, resources)
	drop(items)
	return result
}

fn boot_invoke(c &BootContext, row voidptr, namespace voidptr, resources voidptr) voidptr {
	mut provider := voidptr(0)
	has_id := boot_has(row, 'id')
	if has_id < 0 { return unsafe { nil } }
	if has_id != 0 {
		id := boot_field(row, 'id')
		if id == unsafe { nil } { return id }
		provider = C.PyObject_GetItem(resources, id)
		drop(id)
	} else {
		name := boot_field(row, 'module')
		if name == unsafe { nil } { return name }
		contains := C.PySequence_Contains(namespace, name)
		if contains < 0 { drop(name); return unsafe { nil } }
		if contains != 0 { provider = C.PyObject_GetItem(namespace, name) }
		else {
			importer := c.resolve('__import__')
			if importer == unsafe { nil } { drop(name); return importer }
			wildcard := py_string('*')
			fromlist := C.PyList_New(1)
			C.PyList_SetItem(fromlist, 0, wildcard)
			kwargs := C.PyDict_New()
			C.PyDict_SetItemString(kwargs, c'fromlist', fromlist)
			args := boot_tuple([name])
			provider = C.PyObject_Call(importer, args, kwargs)
			drop(args)
			drop(fromlist)
			drop(kwargs)
			drop(importer)
		}
		drop(name)
	}
	if provider == unsafe { nil } { return provider }
	options := boot_options(c, row, resources)
	if options == unsafe { nil } || pending_error() {
		boot_pin(c, ['provider', 'options'], [provider, options])
		drop(provider)
		drop(options)
		return unsafe { nil }
	}
	getter := c.resolve('getattr')
	if getter == unsafe { nil } { boot_pin(c, ['provider', 'options'], [provider, options]); drop(provider); drop(options); return getter }
	name := boot_field(row, 'name')
	if name == unsafe { nil } { boot_pin(c, ['provider', 'options'], [provider, options]); drop(getter); drop(provider); drop(options); return name }
	target := boot_call(getter, [provider, name])
	drop(name)
	drop(getter)
	if target == unsafe { nil } { boot_pin(c, ['provider', 'options'], [provider, options]); drop(provider); drop(options); return target }
	arguments := boot_row_arguments(c, row, resources, 'arguments')
	if arguments == unsafe { nil } { boot_pin(c, ['provider', 'options'], [provider, options]); drop(target); drop(provider); drop(options); return arguments }
	args := C.PySequence_Tuple(arguments)
	drop(arguments)
	if args == unsafe { nil } { boot_pin(c, ['provider', 'options'], [provider, options]); drop(target); drop(provider); drop(options); return args }
	result := C.PyObject_Call(target, args, options)
	drop(args)
	drop(target)
	boot_pin(c, ['provider', 'options'], [provider, options])
	drop(provider)
	drop(options)
	return result
}

fn boot_primitive(c &BootContext, name string, row voidptr, namespace voidptr, resources voidptr) voidptr {
	if name in ['release', 'release_since'] {
		mut ids := voidptr(0)
		if name == 'release_since' {
			factory := c.resolve('tuple')
			if factory == unsafe { nil } { return factory }
			ids = boot_call(factory, [resources])
			drop(factory)
			if ids == unsafe { nil } { return ids }
		} else { ids = boot_field(row, 'ids') }
		if ids == unsafe { nil } { return ids }
		iterator := C.PyObject_GetIter(ids)
		drop(ids)
		if iterator == unsafe { nil } { return iterator }
		mut ident := voidptr(0)
		for {
			next := C.PyIter_Next(iterator)
			if next == unsafe { nil } { break }
			drop(ident)
			ident = next
			if name == 'release_since' {
				factory := c.resolve('type')
				if factory == unsafe { nil } { break }
				actual_type := boot_call(factory, [ident])
				drop(factory)
				if actual_type == unsafe { nil } { break }
				integer := c.resolve('int')
				if integer == unsafe { nil } { drop(actual_type); break }
				is_integer := actual_type == integer
				drop(actual_type)
				drop(integer)
				if !is_integer { continue }
				boundary := boot_field(row, 'id')
				if boundary == unsafe { nil } { break }
				comparison := C.PyObject_RichCompareBool(ident, boundary, 4)
				drop(boundary)
				if comparison < 0 { break }
				if comparison == 0 { continue }
			}
			owners := boot_field(resources, 'owners')
			if owners == unsafe { nil } { break }
			protected := C.PySequence_Contains(owners, ident)
			drop(owners)
			if protected < 0 { break }
			if protected == 0 && C.PyObject_DelItem(resources, ident) != 0 { break }
		}
		boot_pin(c, ['ident'], [ident])
		drop(ident)
		drop(iterator)
		return if pending_error() { unsafe { nil } } else { py_none() }
	}
	if name == 'checkpoint' {
		zero := C.PyLong_FromLongLong(0)
		result := boot_default(resources, 'next_id', zero)
		drop(zero)
		return result
	}
	if name == 'enter_existing' {
		id := boot_field(row, 'id')
		if id == unsafe { nil } { return id }
		manager := C.PyObject_GetItem(resources, id)
		drop(id)
		if manager == unsafe { nil } { return manager }
		entered := boot_method(manager, '__enter__', [])
		if entered == unsafe { nil } { boot_pin(c, ['manager'], [manager]); drop(manager); return entered }
		ident := boot_register(c, resources, entered)
		drop(entered)
		if ident == unsafe { nil } { boot_pin(c, ['manager'], [manager]); drop(manager); return ident }
		owners := boot_field(resources, 'owners')
		if owners == unsafe { nil } { boot_pin(c, ['manager', 'ident'], [manager, ident]); drop(manager); drop(ident); return owners }
		status := C.PyObject_SetItem(owners, ident, manager)
		drop(owners)
		boot_pin(c, ['manager', 'ident'], [manager, ident])
		drop(manager)
		if status != 0 { drop(ident); return unsafe { nil } }
		return ident
	}
	if name == 'dictionary' {
		factory := c.resolve('dict')
		zipper := c.resolve('zip')
		if factory == unsafe { nil } || zipper == unsafe { nil } { drop(factory); drop(zipper); return unsafe { nil } }
		keys_input := boot_field(row, 'keys')
		if keys_input == unsafe { nil } { drop(factory); drop(zipper); return keys_input }
		keys := boot_arguments(c, keys_input, resources)
		drop(keys_input)
		if keys == unsafe { nil } { drop(factory); drop(zipper); return keys }
		values_input := boot_field(row, 'values')
		if values_input == unsafe { nil } { drop(factory); drop(zipper); drop(keys); return values_input }
		values := boot_arguments(c, values_input, resources)
		drop(values_input)
		if values == unsafe { nil } { drop(factory); drop(zipper); drop(keys); return values }
		pairs := boot_call(zipper, [keys, values])
		drop(keys)
		drop(values)
		drop(zipper)
		if pairs == unsafe { nil } { drop(factory); return pairs }
		value := boot_call(factory, [pairs])
		drop(pairs)
		drop(factory)
		if value == unsafe { nil } { return value }
		ident := boot_register(c, resources, value)
		drop(value)
		return ident
	}
	if name == 'mapping_unpack' {
		helper := c.resolve('_boot_mapping')
		if helper == unsafe { nil } { return helper }
		id := boot_field(row, 'id')
		if id == unsafe { nil } { drop(helper); return id }
		mapping := C.PyObject_GetItem(resources, id)
		drop(id)
		if mapping == unsafe { nil } { drop(helper); return mapping }
		value := boot_call(helper, [mapping])
		drop(mapping)
		drop(helper)
		if value == unsafe { nil } { return value }
		ident := boot_register(c, resources, value)
		drop(value)
		return ident
	}
	if name == 'print' {
		options := boot_options(c, row, resources)
		if options == unsafe { nil } || pending_error() { boot_pin(c, ['options'], [options]); drop(options); return unsafe { nil } }
		mut target := voidptr(0)
		lookup_name := boot_literal('get')
		lookup := C.PyObject_GetAttr(namespace, lookup_name)
		drop(lookup_name)
		if lookup == unsafe { nil } { boot_pin(c, ['options'], [options]); drop(options); return lookup }
		fallback := c.resolve('print')
		if fallback == unsafe { nil } { boot_pin(c, ['options'], [options]); drop(lookup); drop(options); return fallback }
		key := boot_literal('print')
		target = boot_call(lookup, [key, fallback])
		drop(fallback)
		drop(key)
		drop(lookup)
		if target == unsafe { nil } { boot_pin(c, ['options'], [options]); drop(options); return target }
		mut args := voidptr(0)
		data := boot_field(row, 'data')
		if data == unsafe { nil } { boot_pin(c, ['options'], [options]); drop(target); drop(options); return data }
		args = boot_tuple([data])
		drop(data)
		if args == unsafe { nil } { boot_pin(c, ['options'], [options]); drop(target); drop(options); return args }
		value := C.PyObject_Call(target, args, options)
		drop(args)
		drop(target)
		if value == unsafe { nil } { boot_pin(c, ['options'], [options]); drop(options); return value }
		drop(value)
		drop(options)
		return py_none()
	}
	if name == 'function_is' {
		name_ := boot_field(row, 'name')
		if name_ == unsafe { nil } { return name_ }
		left := C.PyObject_GetItem(namespace, name_)
		drop(name_)
		if left == unsafe { nil } { return left }
		reference := boot_field(row, 'reference')
		if reference == unsafe { nil } { drop(left); return reference }
		right := C.PyObject_GetItem(namespace, reference)
		drop(reference)
		if right == unsafe { nil } { drop(left); return right }
		result := C.PyBool_FromLong(if left == right { 1 } else { 0 })
		drop(left)
		drop(right)
		return result
	}
	if name == 'borrow' || name == 'borrow_global' {
		source := if name == 'borrow' { boot_field(resources, 'values') } else { own(namespace) }
		if source == unsafe { nil } { return source }
		key := boot_field(row, 'name')
		if key == unsafe { nil } { drop(source); return key }
		value := C.PyObject_GetItem(source, key)
		drop(key)
		drop(source)
		if value == unsafe { nil } { return value }
		result := boot_register(c, resources, value)
		drop(value)
		return result
	}
	if name == 'retain' {
		encoded := boot_field(row, 'value')
		if encoded == unsafe { nil } { return encoded }
		items := C.PyList_New(1)
		C.PyList_SetItem(items, 0, encoded)
		values := boot_arguments(c, items, resources)
		drop(items)
		if values == unsafe { nil } { return values }
		result := boot_register(c, resources, C.PyList_GetItem(values, 0))
		drop(values)
		return result
	}
	if name in ['sequence', 'tuple'] {
		items := boot_field(row, 'arguments')
		if items == unsafe { nil } { return items }
		values := boot_arguments(c, items, resources)
		drop(items)
		if values == unsafe { nil } { return values }
		value := if name == 'tuple' { C.PySequence_Tuple(values) } else { own(values) }
		drop(values)
		if value == unsafe { nil } { return value }
		result := boot_register(c, resources, value)
		drop(value)
		return result
	}
	if name in ['is_none', 'setattr', 'iterate', 'unpack_pair'] {
		mut getter := voidptr(0)
		if name in ['setattr', 'iterate'] {
			getter = c.resolve(if name == 'iterate' { 'next' } else { name })
			if getter == unsafe { nil } { return getter }
		}
		defer { drop(getter) }
		id := boot_field(row, 'id')
		if id == unsafe { nil } { return id }
		mut value := C.PyObject_GetItem(resources, id)
		drop(id)
		if value == unsafe { nil } { return value }
		defer { drop(value) }
		if name == 'is_none' {
			none_ := py_none()
			result := C.PyBool_FromLong(if value == none_ { 1 } else { 0 })
			drop(none_)
			return result
		}
		if name == 'unpack_pair' {
			helper := c.resolve('_boot_pair')
			if helper == unsafe { nil } { return helper }
			pair := boot_call(helper, [value])
			drop(helper)
			if pair == unsafe { nil } { return pair }
			first_value := own(C.PyTuple_GetItem(pair, 0))
			second_value := own(C.PyTuple_GetItem(pair, 1))
			drop(pair)
			drop(value)
			value = unsafe { nil }
			first := boot_register(c, resources, first_value)
			if first == unsafe { nil } {
				boot_pin(c, ['first', 'second'], [first_value, second_value])
				drop(first_value)
				drop(second_value)
				return first
			}
			second := boot_register(c, resources, second_value)
			boot_pin(c, ['first', 'second'], [first_value, second_value])
			drop(first_value)
			drop(second_value)
			if second == unsafe { nil } { drop(first); return second }
			result := C.PyList_New(2)
			C.PyList_SetItem(result, 0, first)
			C.PyList_SetItem(result, 1, second)
			return result
		}
		if name == 'iterate' {
			item := boot_call(getter, [value])
			drop(value)
			value = unsafe { nil }
			drop(getter)
			getter = unsafe { nil }
			if item == unsafe { nil } {
				stop := c.resolve('StopIteration')
				if stop == unsafe { nil } { return stop }
				matches := C.PyErr_GivenExceptionMatches(C.PyErr_Occurred(), stop)
				drop(stop)
				if matches == 0 { return item }
				C.PyErr_Clear()
				result := C.PyDict_New()
				flag := C.PyBool_FromLong(1)
				C.PyDict_SetItemString(result, c'done', flag)
				drop(flag)
				return result
			}
			id_ := boot_register(c, resources, item)
			drop(item)
			if id_ == unsafe { nil } { return id_ }
			result := C.PyDict_New()
			flag := C.PyBool_FromLong(0)
			C.PyDict_SetItemString(result, c'done', flag)
			C.PyDict_SetItemString(result, c'value', id_)
			drop(flag)
			drop(id_)
			return result
		}
		attribute := boot_field(row, 'name')
		if attribute == unsafe { nil } { return attribute }
		if name == 'setattr' {
			encoded := boot_field(row, 'value')
			if encoded == unsafe { nil } { drop(attribute); return encoded }
			items := C.PyList_New(1)
			C.PyList_SetItem(items, 0, encoded)
			values := boot_arguments(c, items, resources)
			drop(items)
			if values == unsafe { nil } { drop(attribute); return values }
			assigned := own(C.PyList_GetItem(values, 0))
			drop(values)
			result := boot_call(getter, [value, attribute, assigned])
			drop(assigned)
			drop(attribute)
			return result
		}

	}
	// The remaining archive, pool and exceptional-owner boundaries retain
	// their independent Python implementation during this bounded stage.
	return c.resolve('NotImplemented')
}

pub fn boot_entry(operation &char, namespace voidptr, arguments voidptr, pins voidptr) voidptr {
	C.GC_allow_register_threads()
	mut registered := false
	if C.GC_thread_is_registered() == 0 {
		mut stack := C.GC_stack_base{}
		if C.GC_get_stack_base(&stack) != 0 { return C.PyErr_NoMemory() }
		registered = C.GC_register_my_thread(&stack) == 0
		if !registered { return C.PyErr_NoMemory() }
	}
	defer { if registered { C.GC_unregister_my_thread() } }
	context := BootContext{ namespace: namespace, builtins: C.PyEval_GetBuiltins(), pins: pins }
	name := unsafe { operation.vstring() }
	if name !in ['register'] && C.PyErr_CheckSignals() != 0 { return unsafe { nil } }
	result := match name {
		'arguments' { boot_arguments(unsafe { &context }, C.PyTuple_GetItem(arguments, 0), C.PyTuple_GetItem(arguments, 1)) }
		'invoke' { boot_invoke(unsafe { &context }, C.PyTuple_GetItem(arguments, 0), C.PyTuple_GetItem(arguments, 1), C.PyTuple_GetItem(arguments, 2)) }
		'register' { boot_register(unsafe { &context }, C.PyTuple_GetItem(arguments, 0), C.PyTuple_GetItem(arguments, 1)) }
		'primitive' { boot_primitive(unsafe { &context }, string_value(C.PyTuple_GetItem(arguments, 0)), C.PyTuple_GetItem(arguments, 1), C.PyTuple_GetItem(arguments, 2), C.PyTuple_GetItem(arguments, 3)) }
		else { unsafe { nil } }
	}
	if pending_error() { return unsafe { nil } }
	if result == unsafe { nil } {
		error_type := unsafe { C.PyDict_GetItemString(context.builtins, c'RuntimeError') }
		message := py_string('unsupported native boot adapter operation: ' + name)
		C.PyErr_SetObject(error_type, message)
		drop(message)
	}
	return result
}
