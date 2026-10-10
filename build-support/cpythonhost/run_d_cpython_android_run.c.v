// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

// Every owned CPython reference belongs to a synchronous expression or a
// named local. The former is explicitly consumed at its Python boundary;
// failed named scopes are retained by the real binding traceback.
struct RunScope {
	c     &BootContext
	named []string
mut:
	pinned bool
	values map[string]voidptr
	order  []string
}

fn (mut s RunScope) put(name string, value voidptr) voidptr {
	if value == unsafe { nil } { return value }
	if previous := s.values[name] { drop(previous) } else { s.order << name }
	s.values[name] = value
	return value
}

fn (mut s RunScope) take(name string) voidptr {
	value := s.values[name] or { return unsafe { nil } }
	s.values.delete(name)
	return value
}

fn (mut s RunScope) release(names []string) {
	for name in names {
		if value := s.values[name] {
			s.values.delete(name)
			drop(value)
		}
	}
}

fn (mut s RunScope) finish() {
	if pending_error() && s.named.len != 0 && !s.pinned {
		mut values := []voidptr{cap: s.named.len}
		for name in s.named { values << (s.values[name] or { unsafe { nil } }) }
		boot_pin(s.c, s.named, values)
	}
	// A pending expression unwinds before the frame's named locals retire.
	for i := s.order.len - 1; i >= 0; i-- {
		name := s.order[i]
		if name !in s.named { s.release([name]) }
	}
	s.release(s.named)
}

fn (mut s RunScope) global(slot string, name string) voidptr {
	if pending_error() { return unsafe { nil } }
	return s.put(slot, s.c.resolve(name))
}

fn (mut s RunScope) field(slot string, owner voidptr, name string) voidptr {
	if pending_error() { return unsafe { nil } }
	return s.put(slot, boot_field(owner, name))
}

fn (mut s RunScope) item(slot string, owner voidptr, key voidptr) voidptr {
	if pending_error() { return unsafe { nil } }
	return s.put(slot, C.PyObject_GetItem(owner, key))
}

fn (mut s RunScope) attr(slot string, owner voidptr, name string) voidptr {
	if pending_error() { return unsafe { nil } }
	key := boot_literal(name)
	if key == unsafe { nil } { return key }
	result := C.PyObject_GetAttr(owner, key)
	drop(key)
	return s.put(slot, result)
}

fn (mut s RunScope) default_(slot string, owner voidptr, name string, empty voidptr) voidptr {
	if pending_error() {
		drop(empty)
		return unsafe { nil }
	}
	result := boot_default(owner, name, empty)
	drop(empty)
	return s.put(slot, result)
}

fn (mut s RunScope) call(slot string, target voidptr, arguments []voidptr) voidptr {
	if pending_error() { return unsafe { nil } }
	return s.put(slot, boot_call(target, arguments))
}

// The fixed table is owned only during this synchronous Python syntax
// call. Each operand is transferred once; neither binding traceback retains
// the capsule after returning or failing.
struct RunExpression {
mut:
	values [4]voidptr
	count  i32
}

fn C.PyCapsule_New(voidptr, &char, voidptr) voidptr
fn C.PyCapsule_GetPointer(voidptr, &char) voidptr
fn C.PyErr_SetString(voidptr, &char)

@[c_extern]
__global C.PyExc_SystemError voidptr

pub fn run_take(capsule voidptr, index i32) voidptr {
	mut state := unsafe { &RunExpression(C.PyCapsule_GetPointer(capsule, c'vinix.android.run.expression')) }
	if state == unsafe { nil } { return unsafe { nil } }
	if index < 0 || index >= state.count || state.values[index] == unsafe { nil } {
		C.PyErr_SetString(unsafe { voidptr(C.PyExc_SystemError) }, c'invalid Android expression operand')
		return unsafe { nil }
	}
	value := state.values[index]
	state.values[index] = unsafe { nil }
	return value
}

fn (mut s RunScope) syntax(slot string, binding string, operands []string) voidptr {
	if pending_error() { return unsafe { nil } }
	target := s.c.resolve(binding)
	if target == unsafe { nil } { return target }
	mut state := unsafe { &RunExpression(C.malloc(sizeof(RunExpression))) }
	if state == unsafe { nil } {
		drop(target)
		return C.PyErr_NoMemory()
	}
	unsafe { *state = RunExpression{ count: i32(operands.len) } }
	for i, name in operands { state.values[i] = s.take(name) }
	capsule := C.PyCapsule_New(state, c'vinix.android.run.expression', unsafe { nil })
	mut result := voidptr(0)
	if capsule != unsafe { nil } { result = boot_call(target, [capsule]) }
	drop(capsule)
	drop(target)
	for i := operands.len - 1; i >= 0; i-- { drop(state.values[i]) }
	unsafe { C.free(state) }
	return s.put(slot, result)
}

fn (mut s RunScope) apply(slot string, target string, arguments string, options string) voidptr {
	return s.syntax(slot, '_run_apply', [target, arguments, options])
}

fn (mut s RunScope) has(owner voidptr, name string) i32 {
	if pending_error() { return -1 }
	return boot_has(owner, name)
}

fn (mut s RunScope) equal(value voidptr, name string) i32 {
	if pending_error() { return -1 }
	literal := boot_literal(name)
	if literal == unsafe { nil } { return -1 }
	result := C.PyObject_RichCompareBool(value, literal, 2)
	drop(literal)
	return result
}

fn run_argument(c &BootContext, kind voidptr, value voidptr, context voidptr, resources voidptr) voidptr {
	mut s := RunScope{ c: unsafe { c } }
	defer { s.finish() }
	if s.equal(kind, 'path') != 0 {
		target := s.global('target', 'Path')
		result := s.call('result', target, [value])
		s.release(['target'])
		return run_return(result)
	}
	if s.equal(kind, 'bytes') != 0 {
		bytes_ := s.global('bytes', 'bytes')
		target := s.attr('target', bytes_, 'fromhex')
		s.release(['bytes'])
		result := s.call('result', target, [value])
		s.release(['target'])
		return run_return(result)
	}
	if s.equal(kind, 'callback') != 0 {
		target := s.global('target', '_run_callback')
		result := s.call('result', target, [value, context, resources])
		s.release(['target'])
		return run_return(result)
	}
	if s.equal(kind, 'constant') != 0 {
		getter := s.global('getter', 'getattr')
		zero := s.put('zero', C.PyLong_FromLongLong(0))
		module := s.item('module', value, zero)
		s.release(['zero'])
		provider := s.item('provider', context, module)
		s.release(['module'])
		one := s.put('one', C.PyLong_FromLongLong(1))
		name := s.item('name', value, one)
		s.release(['one'])
		result := s.call('result', getter, [provider, name])
		s.release(['name', 'provider', 'getter'])
		return run_return(result)
	}
	if pending_error() { return unsafe { nil } }
	return own(value)
}

fn run_arguments(c &BootContext, items voidptr, context voidptr, resources voidptr) voidptr {
	defer { boot_pin(c, ['items', 'context', 'resources'], [items, context, resources]) }
	iterator := C.PyObject_GetIter(items)
	if iterator == unsafe { nil } { return iterator }
	result := C.PyList_New(0)
	if result == unsafe { nil } {
		boot_pin(c, ['.0'], [iterator])
		drop(iterator)
		return result
	}
	pair_helper := c.resolve('_boot_pair')
	if pair_helper == unsafe { nil } {
		boot_pin(c, ['.0'], [iterator])
		drop(iterator)
		drop(result)
		return pair_helper
	}
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
		argument := run_argument(c, kind, value, context, resources)
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
	if pending_error() {
		drop(result)
		return unsafe { nil }
	}
	return result
}

fn run_invoke(c &BootContext, row voidptr, context voidptr, resources voidptr) voidptr {
	mut s := RunScope{ c: unsafe { c }, named: ['provider'] }
	defer { s.finish() }
	mut provider := voidptr(0)
	id := s.has(row, 'id')
	if id < 0 { return unsafe { nil } }
	if id != 0 {
		contexts := s.field('contexts', resources, 'contexts')
		ident := s.field('ident', row, 'id')
		entered := s.item('entered', contexts, ident)
		s.release(['contexts', 'ident'])
		one := s.put('one', C.PyLong_FromLongLong(1))
		provider = s.item('provider', entered, one)
		s.release(['one', 'entered'])
	} else {
		modules := s.field('modules', resources, 'modules')
		get := s.attr('get', modules, 'get')
		s.release(['modules'])
		module := s.field('module', row, 'module')
		found := s.call('found', get, [module])
		s.release(['module', 'get'])
		if pending_error() { return unsafe { nil } }
		truth := C.PyObject_IsTrue(found)
		if truth < 0 { return unsafe { nil } }
		if truth != 0 {
			provider = s.put('provider', own(found))
		} else {
			s.release(['found'])
			get_context := s.attr('get_context', context, 'get')
			name := s.field('name', row, 'module')
			provider = s.call('provider', get_context, [name])
			s.release(['name', 'get_context'])
		}
		s.release(['found'])
		if pending_error() { return unsafe { nil } }
		none_ := py_none()
		if provider == none_ {
			importlib_ := s.global('importlib', 'importlib')
			importer := s.attr('importer', importlib_, 'import_module')
			s.release(['importlib'])
			name := s.field('module_name', row, 'module')
			provider = s.call('provider', importer, [name])
			s.release(['module_name', 'importer'])
		}
		drop(none_)
	}
	getter := s.global('getter', 'getattr')
	name := s.field('method_name', row, 'name')
	s.call('target', getter, [provider, name])
	s.release(['method_name', 'getter'])
	items := s.default_('items', row, 'arguments', C.PyList_New(0))
	if pending_error() { return unsafe { nil } }
	s.put('arguments', run_arguments(c, items, context, resources))
	s.release(['items'])
	s.default_('options', row, 'options', C.PyDict_New())
	result := s.apply('result', 'target', 'arguments', 'options')
	s.release(['options', 'arguments', 'target'])
	return run_return(result)
}

fn run_return(value voidptr) voidptr {
	if pending_error() { return unsafe { nil } }
	return own(value)
}

// The caller transfers the comprehension iterator after retiring its source
// expression. Loop locals survive through the next iterator callback.
fn run_mapped(c &BootContext, iterator voidptr, mode string, local string) voidptr {
	mut s := RunScope{ c: unsafe { c }, named: [local] }
	result := C.PyList_New(0)
	if result == unsafe { nil } {
		boot_pin(c, ['.0'], [iterator])
		drop(iterator)
		return result
	}
	for {
		item := C.PyIter_Next(iterator)
		if item == unsafe { nil } { break }
		value := s.put(local, item)
		mut converted := voidptr(0)
		if mode == 'hex' {
			target := s.attr('target', value, 'hex')
			converted = s.call('converted', target, [])
			s.release(['target'])
		} else {
			target := s.global('target', mode)
			converted = s.call('converted', target, [value])
			s.release(['target'])
		}
		if pending_error() { break }
		status := C.PyList_Append(result, converted)
		s.release(['converted'])
		if status != 0 { break }
	}
	boot_pin(c, ['.0', local], [iterator, s.values[local] or { unsafe { nil } }])
	s.pinned = true
	s.finish()
	drop(iterator)
	if pending_error() {
		drop(result)
		return unsafe { nil }
	}
	return result
}

fn run_selection(name string) voidptr {
	selected := if name == '' { py_none() } else { boot_literal(name) }
	if selected == unsafe { nil } { return selected }
	native := C.PyBool_FromLong(if name in ['invoke_bytes', 'group_set', 'group_truth', 'stream_method',
		'characters', 'length', 'item', 'contains', 'constant', 'constant_bytes', 'builtin', 'numeric',
		'observed', 'iterdir', 'glob', 'rglob', 'read_bytes', 'read_handle', 'attribute_bytes',
		'json_loads', 'json_dumps', 'bytes_decode', 'bytes_int', 'type_name', 'str_attribute',
		'run', 'which', 'environ', 'platform', 'strip', 'import', 'args_item', 'args_append',
		'parser_error', 'args_set', 'print']! {
		1
	} else {
		0
	})
	if native == unsafe { nil } {
		drop(selected)
		return native
	}
	result := C.PyTuple_New(2)
	if result == unsafe { nil } {
		drop(native)
		drop(selected)
		return result
	}
	C.PyTuple_SetItem(result, 0, selected)
	C.PyTuple_SetItem(result, 1, native)
	return result
}

fn run_select(operation voidptr) voidptr {
	for name in ['invoke', 'invoke_bytes', 'error_attribute', 'group_get', 'group_set', 'group_truth',
		'group_method', 'group_bytes', 'stream_method', 'thread_start', 'enter_context', 'exit_context',
		'load_source', 'characters', 'slice', 'item', 'contains', 'constant', 'constant_bytes',
		'python_version', 'builtin', 'numeric', 'raise', 'exception_is', 'observed', 'path', 'iterdir',
		'glob', 'rglob', 'join', 'stat', 'rmtree', 'copy2', 'link', 'readlink', 'inode_contains',
		'inode_reset', 'inode_link', 'inode_set', 'length', 'read_bytes', 'open_read', 'read_handle',
		'exit_handle', 'json_loads', 'json_dumps', 'bytes_decode', 'bytes_int', 'type_name', 'attribute',
		'attribute_bytes', 'str_attribute', 'function', 'run', 'which', 'environ', 'platform',
		'strip', 'import', 'api', 'args_set', 'args_item', 'args_append', 'parser_error', 'print',
		'roblox_validate', 'tar_open', 'tar_next', 'tar_extract', 'tar_info', 'tar_add', 'tar_exit']! {
		literal := boot_literal(name)
		if literal == unsafe { nil } { return literal }
		member := name in ['iterdir', 'glob', 'rglob', 'rmtree', 'copy2', 'link', 'readlink']
		comparison := if member {
			C.PyObject_RichCompareBool(literal, operation, 2)
		} else {
			C.PyObject_RichCompareBool(operation, literal, 2)
		}
		drop(literal)
		if comparison < 0 { return unsafe { nil } }
		if comparison != 0 { return run_selection(name) }
	}
	return run_selection('')
}

fn run_primitive(c &BootContext, operation string, operation_value voidptr, row voidptr, context voidptr, resources voidptr, path voidptr) voidptr {
	mut s := RunScope{ c: unsafe { c }, named: ['method', 'result', 'value'] }
	defer { s.finish() }
	if operation == 'invoke_bytes' {
		result := s.put('called', run_invoke(c, row, context, resources))
		target := s.attr('target', result, 'hex')
		s.release(['called'])
		returned := s.call('returned', target, [])
		s.release(['target'])
		return run_return(returned)
	}
	if operation == 'group_truth' {
		getter := s.global('getter', 'bool')
		group := s.field('group', resources, 'group')
		name := s.field('name', row, 'name')
		value := s.item('group_value', group, name)
		s.release(['group', 'name'])
		result := s.call('returned', getter, [value])
		s.release(['group_value', 'getter'])
		return run_return(result)
	}
	if operation == 'group_set' {
		value := s.field('rhs', row, 'value')
		group := s.field('group', resources, 'group')
		name := s.field('name', row, 'name')
		if pending_error() { return unsafe { nil } }
		status := C.PyObject_SetItem(group, name, value)
		s.release(['rhs', 'group', 'name'])
		if status != 0 { return unsafe { nil } }
		return py_none()
	}
	if operation == 'stream_method' {
		getter := s.global('getter3', 'getattr')
		getter2 := s.global('getter2', 'getattr')
		getter1 := s.global('getter1', 'getattr')
		sys_ := s.field('sys', context, 'sys')
		stream := s.field('stream', row, 'stream')
		first := s.call('first', getter1, [sys_, stream])
		s.release(['stream', 'sys', 'getter1'])
		field := s.field('field', row, 'field')
		second := s.call('second', getter2, [first, field])
		s.release(['field', 'first', 'getter2'])
		name := s.field('name', row, 'name')
		target := s.call('target', getter, [second, name])
		s.release(['name', 'second', 'getter3'])
		items := s.default_('items', row, 'arguments', C.PyList_New(0))
		if pending_error() { return unsafe { nil } }
		s.put('arguments', run_arguments(c, items, context, resources))
		s.release(['items'])
		s.put('options', C.PyDict_New())
		result := s.apply('returned', 'target', 'arguments', 'options')
		s.release(['options', 'arguments', 'target'])
		return run_return(result)
	}
	if operation == 'characters' || operation == 'length' {
		target := s.global('target', if operation == 'characters' { 'list' } else { 'len' })
		value := s.field('input', row, if operation == 'characters' { 'value' } else { 'data' })
		result := s.call('returned', target, [value])
		s.release(['input', 'target'])
		return run_return(result)
	}
	if operation == 'item' || operation == 'contains' {
		mut value := voidptr(0)
		mut key := voidptr(0)
		if operation == 'contains' {
			key = s.field('key', row, 'key')
			value = s.field('input', row, 'value')
		} else {
			value = s.field('input', row, 'value')
			key = s.field('key', row, 'key')
		}
		if pending_error() { return unsafe { nil } }
		if operation == 'contains' {
			truth := C.PySequence_Contains(value, key)
			s.release(['key', 'input'])
			if truth < 0 { return unsafe { nil } }
			return C.PyBool_FromLong(truth)
		}
		result := s.item('returned', value, key)
		s.release(['input', 'key'])
		return run_return(result)
	}
	if operation == 'constant' {
		getter := s.global('getter', 'getattr')
		module := s.field('module', row, 'module')
		owner := s.item('owner', context, module)
		s.release(['module'])
		name := s.field('name', row, 'name')
		result := s.call('returned', getter, [owner, name])
		s.release(['name', 'owner', 'getter'])
		return run_return(result)
	}
	if operation == 'constant_bytes' {
		name := s.field('name', row, 'name')
		values := s.item('values', context, name)
		s.release(['name'])
		if pending_error() { return unsafe { nil } }
		s.put('iterator', C.PyObject_GetIter(values))
		s.release(['values'])
		if pending_error() { return unsafe { nil } }
		result := s.put('returned', run_mapped(c, s.take('iterator'), 'hex', 'value'))
		return run_return(result)
	}
	if operation == 'builtin' || operation == 'numeric' {
		getter := s.global('getter', 'getattr')
		module := s.global('module', if operation == 'builtin' { 'builtins' } else { 'operator' })
		name := s.field('name', row, 'name')
		target := s.call('target', getter, [module, name])
		s.release(['name', 'module', 'getter'])
		s.field('arguments', row, 'arguments')
		options := s.put('options', C.PyDict_New())
		result := s.apply('returned', 'target', 'arguments', 'options')
		s.release(['options', 'arguments', 'target'])
		return run_return(result)
	}
	if operation == 'observed' {
		target := s.field('target', resources, 'observed')
		result := s.call('returned', target, [])
		s.release(['target'])
		return run_return(result)
	}
	if operation == 'iterdir' || operation == 'glob' || operation == 'rglob' {
		getter := s.global('getter', 'getattr')
		opname := s.put('opname', own(operation_value))
		target := s.call('target', getter, [path, opname])
		s.release(['opname', 'getter'])
		s.default_('arguments', row, 'arguments', C.PyList_New(0))
		options := s.put('options', C.PyDict_New())
		values := s.apply('values', 'target', 'arguments', 'options')
		s.release(['options', 'arguments', 'target'])
		if pending_error() { return unsafe { nil } }
		s.put('iterator', C.PyObject_GetIter(values))
		s.release(['values'])
		if pending_error() { return unsafe { nil } }
		result := s.put('returned', run_mapped(c, s.take('iterator'), 'str', 'item'))
		return run_return(result)
	}
	if operation == 'read_bytes' || operation == 'read_handle' || operation == 'attribute_bytes' {
		mut receiver := path
		if operation == 'read_handle' {
			handles := s.field('handles', resources, 'handles')
			ident := s.field('ident', row, 'id')
			pair := s.item('pair', handles, ident)
			s.release(['handles', 'ident'])
			one := s.put('one', C.PyLong_FromLongLong(1))
			receiver = s.item('receiver', pair, one)
			s.release(['one', 'pair'])
		} else if operation == 'attribute_bytes' {
			getter := s.global('getter', 'getattr')
			args := s.field('args', resources, 'args')
			name := s.field('name', row, 'name')
			receiver = s.call('receiver', getter, [args, name])
			s.release(['name', 'args', 'getter'])
		}
		reader := s.attr('reader', receiver, if operation == 'read_handle' {
			'read'
		} else {
			'read_bytes'
		})
		s.release(['receiver'])
		mut bytes_ := voidptr(0)
		if operation == 'read_handle' {
			limit := s.field('limit', row, 'limit')
			bytes_ = s.call('bytes', reader, [limit])
			s.release(['limit', 'reader'])
		} else {
			bytes_ = s.call('bytes', reader, [])
			s.release(['reader'])
		}
		hex := s.attr('hex', bytes_, 'hex')
		s.release(['bytes'])
		result := s.call('returned', hex, [])
		s.release(['hex'])
		return run_return(result)
	}
	if operation == 'json_loads' || operation == 'json_dumps' {
		module := s.field('module', context, 'json')
		target := s.attr('target', module, if operation == 'json_loads' { 'loads' } else { 'dumps' })
		s.release(['module'])
		data := s.field('data', row, 'data')
		mut result := voidptr(0)
		if operation == 'json_loads' {
			result = s.call('returned', target, [data])
		} else {
			options := s.default_('options', row, 'options', C.PyDict_New())
			s.put('arguments', boot_tuple([data]))
			s.release(['data'])
			result = s.apply('returned', 'target', 'arguments', 'options')
			s.release(['options', 'arguments'])
		}
		s.release(['data', 'target'])
		return run_return(result)
	}
	if operation == 'bytes_decode' || operation == 'bytes_int' {
		mut int_ := voidptr(0)
		if operation == 'bytes_int' { int_ = s.global('int', 'int') }
		bytes_ := s.global('bytes_factory', 'bytes')
		target := s.attr('fromhex', bytes_, 'fromhex')
		s.release(['bytes_factory'])
		data := s.field('data', row, 'data')
		value := s.call('bytes', target, [data])
		s.release(['data', 'fromhex'])
		if operation == 'bytes_int' {
			result := s.call('returned', int_, [value])
			s.release(['bytes', 'int'])
			return run_return(result)
		}
		s.attr('decoder', value, 'decode')
		s.release(['bytes'])
		options := s.default_('options', row, 'options', C.PyDict_New())
		s.put('arguments', C.PyTuple_New(0))
		result := s.apply('returned', 'decoder', 'arguments', 'options')
		s.release(['options', 'arguments', 'decoder'])
		return run_return(result)
	}
	if operation == 'type_name' {
		target := s.global('target', 'type')
		value := s.field('input', row, 'value')
		type_ := s.call('type', target, [value])
		s.release(['input', 'target'])
		result := s.attr('returned', type_, '__name__')
		s.release(['type'])
		return run_return(result)
	}
	if operation == 'str_attribute' {
		getter := s.global('getter', 'getattr')
		args := s.field('args', resources, 'args')
		name := s.field('name', row, 'name')
		value := s.call('value', getter, [
			args,
			name,
		])
		s.release(['name', 'args', 'getter'])

		formatter := s.global('formatter', 'str')
		indexed := s.has(row, 'index')
		if indexed < 0 { return unsafe { nil } }
		mut input := value
		if indexed != 0 {
			index := s.field('index', row, 'index')
			input = s.item('indexed', value, index)
			s.release(['index'])
		}
		result := s.call('returned', formatter, [input])
		s.release(['indexed', 'formatter'])
		return run_return(result)
	}
	if operation == 'which' {
		module := s.field('module', context, 'shutil')
		target := s.attr('target', module, 'which')
		s.release(['module'])
		data := s.field('input', row, 'name')
		result := s.call('returned', target, [data])
		s.release(['input', 'target'])
		return run_return(result)
	}
	if operation == 'run' {
		module := s.field('module', context, 'subprocess')
		target := s.attr('target', module, 'run')
		s.release(['module'])
		data := s.field('input', row, 'arguments')
		options := s.put('options', C.PyDict_New())
		if pending_error() { return unsafe { nil } }
		yes := C.PyBool_FromLong(1)
		if yes == unsafe { nil } { return yes }
		status := C.PyDict_SetItemString(options, c'check', yes)
		drop(yes)
		if status != 0 { return unsafe { nil } }
		s.put('arguments', boot_tuple([data]))
		s.release(['input'])
		result := s.apply('returned', 'target', 'arguments', 'options')
		s.release(['options', 'arguments', 'input', 'target'])
		return run_return(result)
	}
	if operation == 'environ' || operation == 'platform' {
		module := s.field('module', context, if operation == 'environ' { 'os' } else { 'platform' })
		mut target := voidptr(0)
		if operation == 'environ' {
			environment := s.attr('environment', module, 'environ')
			s.release(['module'])
			target = s.attr('target', environment, 'copy')
			s.release(['environment'])
		} else {
			target = s.attr('target', module, 'system')
			s.release(['module'])
		}
		result := s.call('returned', target, [])
		s.release(['target'])
		return run_return(result)
	}
	if operation == 'strip' {
		data := s.field('data', row, 'data')
		target := s.attr('target', data, 'strip')
		s.release(['data'])
		result := s.call('returned', target, [])
		s.release(['target'])
		return run_return(result)
	}
	if operation == 'import' {
		module := s.global('module', 'importlib')
		target := s.attr('target', module, 'import_module')
		s.release(['module'])
		name := s.field('name', row, 'name')
		s.call('ignored', target, [name])
		s.release(['name', 'target', 'ignored'])
		if pending_error() { return unsafe { nil } }
		return py_none()
	}
	if operation == 'args_append' || operation == 'args_item' {
		mut value := voidptr(0)
		if operation == 'args_item' { value = s.field('rhs', row, 'value') }
		getter := s.global('getter', 'getattr')
		args := s.field('args', resources, 'args')
		name := s.field('name', row, 'name')
		receiver := s.call('receiver', getter, [args, name])
		s.release(['name', 'args', 'getter'])
		if operation == 'args_item' {
			key := s.field('key', row, 'key')
			if pending_error() { return unsafe { nil } }
			status := C.PyObject_SetItem(receiver, key, value)
			s.release(['rhs', 'receiver', 'key'])
			if status != 0 { return unsafe { nil } }
		} else {
			target := s.attr('target', receiver, 'append')
			s.release(['receiver'])
			value = s.field('rhs', row, 'value')
			s.call('ignored', target, [value])
			s.release(['rhs', 'target', 'ignored'])
			if pending_error() { return unsafe { nil } }
		}
		return py_none()
	}
	if operation == 'parser_error' {
		parser := s.field('parser', resources, 'parser')
		target := s.attr('target', parser, 'error')
		s.release(['parser'])
		message := s.field('message', row, 'message')
		result := s.call('returned', target, [message])
		s.release(['message', 'target'])
		return run_return(result)
	}

	if operation == 'args_set' {
		mut value := s.field('value', row, 'value')
		kind := s.field('kind', row, 'kind')
		path_kind := s.equal(kind, 'path')
		s.release(['kind'])
		if path_kind < 0 { return unsafe { nil } }
		if path_kind != 0 {
			none_ := py_none()
			if value != none_ {
				factory := s.global('factory', 'Path')
				converted := s.call('converted_value', factory, [value])
				s.release(['factory'])
				value = s.put('value', s.take('converted_value'))
			}
			drop(none_)
		} else {
			kind2 := s.field('kind2', row, 'kind')
			paths_kind := s.equal(kind2, 'paths')
			s.release(['kind2'])
			if paths_kind < 0 { return unsafe { nil } }
			if paths_kind != 0 {
				iterator := C.PyObject_GetIter(value)
				if iterator == unsafe { nil } { return iterator }
				converted := run_mapped(c, iterator, 'Path', 'item')
				s.put('value', converted)
				value = converted
			}
		}
		setter := s.global('setter', 'setattr')
		args := s.field('args', resources, 'args')
		name := s.field('name', row, 'name')
		s.call('ignored', setter, [args, name, value])
		s.release(['name', 'args', 'setter', 'ignored'])
		if pending_error() { return unsafe { nil } }
		return py_none()
	}
	if operation == 'print' {
		target := s.global('target', 'print')
		data := s.field('data', row, 'data')
		stderr_ := s.default_('stderr', row, 'stderr', py_none())
		if pending_error() { return unsafe { nil } }
		truth := C.PyObject_IsTrue(stderr_)
		s.release(['stderr'])
		if truth < 0 { return unsafe { nil } }
		sys_ := s.field('sys', context, 'sys')
		s.attr('file', sys_, if truth != 0 { 'stderr' } else { 'stdout' })
		s.release(['sys'])
		options := s.default_('options', row, 'options', C.PyDict_New())
		s.syntax('ignored', '_run_print', ['target', 'data', 'file', 'options'])
		s.release(['options', 'file', 'data', 'target', 'syntax', 'ignored'])
		if pending_error() { return unsafe { nil } }
		return py_none()
	}
	return c.resolve('NotImplemented')
}

pub fn run_entry(operation &char, namespace voidptr, arguments voidptr, pins voidptr) voidptr {
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
	result := match name {
		'select' { run_select(C.PyTuple_GetItem(arguments, 0)) }
		'arguments' {
			run_arguments(unsafe { &context }, C.PyTuple_GetItem(arguments, 0), C.PyTuple_GetItem(arguments, 1), C.PyTuple_GetItem(arguments, 2))
		}
		'invoke' {
			run_invoke(unsafe { &context }, C.PyTuple_GetItem(arguments, 0), C.PyTuple_GetItem(arguments, 1), C.PyTuple_GetItem(arguments, 2))
		}
		'primitive' {
			run_primitive(unsafe { &context }, string_value(C.PyTuple_GetItem(arguments, 0)), C.PyTuple_GetItem(arguments, 1), C.PyTuple_GetItem(arguments, 2), C.PyTuple_GetItem(arguments, 3), C.PyTuple_GetItem(arguments, 4), C.PyTuple_GetItem(arguments, 5))
		}
		else { unsafe { nil } }
	}
	return result
}
