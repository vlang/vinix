// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonapi

import dl

pub type Ref = voidptr
type Initialize = fn (i32)
type Finalize = fn () i32
type RefOp = fn (Ref)
type Import = fn (&char) Ref
type Attribute = fn (Ref, &char) Ref
type Call = fn (Ref, Ref, Ref) Ref
type UnaryRef = fn (Ref) Ref
type UnaryInt = fn (Ref) i32
type Compare = fn (Ref, Ref, i32) i32
type Size = fn (Ref) isize
type Text = fn (&char, isize) Ref
type NewInt = fn (i64) Ref
type ReadInt = fn (Ref) i64
type NewFloat = fn (f64) Ref
type ReadFloat = fn (Ref) f64
type NewSequence = fn (isize) Ref
type PutSequence = fn (Ref, isize, Ref) i32
type GetSequence = fn (Ref, isize) Ref
type Append = fn (Ref, Ref) i32
type DictNew = fn () Ref
type DictPut = fn (Ref, &char, Ref) i32
type UnicodeData = fn (Ref, &isize) &char
type BytesData = fn (Ref, &&char, &isize) i32
type ErrorOccurred = fn () Ref
type ErrorFetch = fn (&Ref, &Ref, &Ref)
type ErrorString = fn (Ref, &char)
type HasAttribute = fn (Ref, &char) i32
type CapsuleNew = fn (voidptr, &char, voidptr) Ref
type CapsulePointer = fn (Ref, &char) voidptr
type FunctionNew = fn (&Method, Ref, Ref) Ref

// CPython's stable ABI PyMethodDef layout. Names and definitions must remain
// alive until every callable and interpreter thread has retired.
pub struct Method {
pub:
	name     &char
	function voidptr
	flags    i32   = 1 // METH_VARARGS
	doc      &char = unsafe { nil }
}

@[heap]
pub struct Api {
pub:
	handle          voidptr
	initialize      Initialize     = unsafe { nil }
	finalize        Finalize       = unsafe { nil }
	inc             RefOp          = unsafe { nil }
	dec             RefOp          = unsafe { nil }
	import_module   Import         = unsafe { nil }
	attribute       Attribute      = unsafe { nil }
	call            Call           = unsafe { nil }
	stringify       UnaryRef       = unsafe { nil }
	truth           UnaryInt       = unsafe { nil }
	compare         Compare        = unsafe { nil }
	size            Size           = unsafe { nil }
	unicode         Text           = unsafe { nil }
	bytes           Text           = unsafe { nil }
	integer         NewInt         = unsafe { nil }
	boolean         NewInt         = unsafe { nil }
	as_integer      ReadInt        = unsafe { nil }
	floating        NewFloat       = unsafe { nil }
	as_float        ReadFloat      = unsafe { nil }
	tuple           NewSequence    = unsafe { nil }
	tuple_put       PutSequence    = unsafe { nil }
	item            GetSequence    = unsafe { nil }
	list            NewSequence    = unsafe { nil }
	append          Append         = unsafe { nil }
	dict            DictNew        = unsafe { nil }
	dict_put        DictPut        = unsafe { nil }
	unicode_data    UnicodeData    = unsafe { nil }
	bytes_data      BytesData      = unsafe { nil }
	error_occurred  ErrorOccurred  = unsafe { nil }
	error_fetch     ErrorFetch     = unsafe { nil }
	error_string    ErrorString    = unsafe { nil }
	has_attribute   HasAttribute   = unsafe { nil }
	capsule_new     CapsuleNew     = unsafe { nil }
	capsule_pointer CapsulePointer = unsafe { nil }
	function_new    FunctionNew    = unsafe { nil }
	none            Ref
	runtime_error   Ref
}

pub const symbols = ['Py_InitializeEx', 'Py_FinalizeEx', 'Py_IncRef', 'Py_DecRef',
	'PyImport_ImportModule', 'PyObject_GetAttrString', 'PyObject_Call', 'PyObject_Str',
	'PyObject_IsTrue', 'PyObject_RichCompareBool', 'PyObject_Size', 'PyUnicode_FromStringAndSize',
	'PyBytes_FromStringAndSize', 'PyLong_FromLongLong', 'PyLong_AsLongLong', 'PyFloat_FromDouble',
	'PyFloat_AsDouble', 'PyTuple_New', 'PyTuple_SetItem', 'PySequence_GetItem', 'PyList_New',
	'PyList_Append', 'PyDict_New', 'PyDict_SetItemString', 'PyUnicode_AsUTF8AndSize',
	'PyBytes_AsStringAndSize', 'PyErr_Occurred', 'PyErr_Fetch', 'PyErr_SetString',
	'PyObject_HasAttrString', 'PyCapsule_New', 'PyCapsule_GetPointer', 'PyCFunction_NewEx',
	'_Py_NoneStruct', 'PyExc_RuntimeError', 'PyBool_FromLong']

pub fn open(path string) !Api {
	handle := dl.open_opt(path, dl.rtld_now | dl.rtld_global)!
	mut retained := false
	defer { if !retained { dl.close(handle) } }
	mut found := []voidptr{}
	for name in symbols { found << dl.sym_opt(handle, name)! }
	api := Api{
		handle:          handle
		initialize:      unsafe { Initialize(found[0]) }
		finalize:        unsafe { Finalize(found[1]) }
		inc:             unsafe { RefOp(found[2]) }
		dec:             unsafe { RefOp(found[3]) }
		import_module:   unsafe { Import(found[4]) }
		attribute:       unsafe { Attribute(found[5]) }
		call:            unsafe { Call(found[6]) }
		stringify:       unsafe { UnaryRef(found[7]) }
		truth:           unsafe { UnaryInt(found[8]) }
		compare:         unsafe { Compare(found[9]) }
		size:            unsafe { Size(found[10]) }
		unicode:         unsafe { Text(found[11]) }
		bytes:           unsafe { Text(found[12]) }
		integer:         unsafe { NewInt(found[13]) }
		as_integer:      unsafe { ReadInt(found[14]) }
		floating:        unsafe { NewFloat(found[15]) }
		as_float:        unsafe { ReadFloat(found[16]) }
		tuple:           unsafe { NewSequence(found[17]) }
		tuple_put:       unsafe { PutSequence(found[18]) }
		item:            unsafe { GetSequence(found[19]) }
		list:            unsafe { NewSequence(found[20]) }
		append:          unsafe { Append(found[21]) }
		dict:            unsafe { DictNew(found[22]) }
		dict_put:        unsafe { DictPut(found[23]) }
		unicode_data:    unsafe { UnicodeData(found[24]) }
		bytes_data:      unsafe { BytesData(found[25]) }
		error_occurred:  unsafe { ErrorOccurred(found[26]) }
		error_fetch:     unsafe { ErrorFetch(found[27]) }
		error_string:    unsafe { ErrorString(found[28]) }
		has_attribute:   unsafe { HasAttribute(found[29]) }
		capsule_new:     unsafe { CapsuleNew(found[30]) }
		capsule_pointer: unsafe { CapsulePointer(found[31]) }
		function_new:    unsafe { FunctionNew(found[32]) }
		none:            Ref(found[33])
		runtime_error:   unsafe { *(&Ref(found[34])) }
		boolean:         unsafe { NewInt(found[35]) }
	}
	retained = true
	return api
}

pub fn (api &Api) close_library() { dl.close(api.handle) }

pub fn (api &Api) exception() IError {
	mut kind, value, trace := Ref(unsafe { nil }), Ref(unsafe { nil }), Ref(unsafe { nil })
	api.error_fetch(&kind, &value, &trace)
	defer {
		for item in [kind, value, trace] { if item != unsafe { nil } { api.dec(item) } }
	}
	mut message := 'CPython operation failed'
	if kind != unsafe { nil } {
		name := api.attribute(kind, c'__name__')
		if name != unsafe { nil } {
			mut length := isize(0)
			data := api.unicode_data(name, &length)
			if data != unsafe { nil } { message = unsafe { tos(&u8(data), int(length)).clone() } }
			api.dec(name)
		}
	}
	// Error formatting must not leave a second error on the interpreter.
	if api.error_occurred() != unsafe { nil } {
		mut extra_kind, extra_value, extra_trace := Ref(unsafe { nil }), Ref(unsafe { nil }), Ref(unsafe { nil })
		api.error_fetch(&extra_kind, &extra_value, &extra_trace)
		for item in [extra_kind, extra_value, extra_trace] {
			if item != unsafe { nil } { api.dec(item) }
		}
	}
	return error(message)
}

pub struct Arena {
pub:
	api &Api
mut:
	refs   []Ref
	closed bool
}

pub fn (mut arena Arena) close() {
	if arena.closed { return }
	arena.closed = true
	for index := arena.refs.len - 1; index >= 0; index-- { arena.api.dec(arena.refs[index]) }
	arena.refs.clear()
}

pub fn (mut arena Arena) take(reference Ref) !Ref {
	if arena.closed {
		if reference != unsafe { nil } { arena.api.dec(reference) }
		return error('CPython arena is retired')
	}
	if reference == unsafe { nil } { return arena.api.exception() }
	arena.refs << reference
	return reference
}

pub fn (mut arena Arena) borrow(reference Ref) !Ref {
	if arena.closed || reference == unsafe { nil } {
		return error('invalid CPython borrowed reference')
	}
	arena.api.inc(reference)
	return arena.take(reference)!
}

pub fn (mut arena Arena) text(value string) !Ref {
	arena.require_live()!
	return arena.take(arena.api.unicode(value.str, value.len))!
}

pub fn (mut arena Arena) data(value []u8) !Ref {
	arena.require_live()!
	return arena.take(arena.api.bytes(unsafe { &char(value.data) }, value.len))!
}

pub fn (mut arena Arena) int(value i64) !Ref {
	arena.require_live()!
	return arena.take(arena.api.integer(value))!
}

pub fn (mut arena Arena) boolean(value bool) !Ref {
	arena.require_live()!
	return arena.take(arena.api.boolean(if value { 1 } else { 0 }))!
}

pub fn (mut arena Arena) float(value f64) !Ref {
	arena.require_live()!
	return arena.take(arena.api.floating(value))!
}

pub fn (mut arena Arena) attr(reference Ref, name string) !Ref {
	arena.require_live()!
	return arena.take(arena.api.attribute(reference, name.str))!
}

pub fn (mut arena Arena) load(name string) !Ref {
	arena.require_live()!
	return arena.take(arena.api.import_module(name.str))!
}

pub fn (mut arena Arena) item(reference Ref, index int) !Ref {
	arena.require_live()!
	return arena.take(arena.api.item(reference, index))!
}

pub fn (mut arena Arena) tuple(values []Ref) !Ref {
	arena.require_live()!
	result := arena.take(arena.api.tuple(values.len))!
	for index, value in values {
		arena.api.inc(value) // SetItem steals this new reference, including failure.
		if arena.api.tuple_put(result, index, value) != 0 { return arena.api.exception() }
	}
	return result
}

pub fn (mut arena Arena) list(values []Ref) !Ref {
	arena.require_live()!
	result := arena.take(arena.api.list(0))!
	for value in values { if arena.api.append(result, value) != 0 { return arena.api.exception() } }
	return result
}

pub fn (mut arena Arena) call(target Ref, args []Ref, keywords map[string]Ref) !Ref {
	arena.require_live()!
	arguments := arena.tuple(args)!
	mut dictionary := Ref(unsafe { nil })
	if keywords.len > 0 {
		dictionary = arena.take(arena.api.dict())!
		for name, value in keywords {
			if arena.api.dict_put(dictionary, name.str, value) != 0 { return arena.api.exception() }
		}
	}
	return arena.take(arena.api.call(target, arguments, dictionary))!
}

pub fn (mut arena Arena) method(reference Ref, name string, args []Ref, keywords map[string]Ref) !Ref {
	arena.require_live()!
	return arena.call(arena.attr(reference, name)!, args, keywords)!
}

pub fn (arena &Arena) integer(reference Ref) !i64 {
	arena.require_live()!
	value := arena.api.as_integer(reference)
	if arena.api.error_occurred() != unsafe { nil } { return arena.api.exception() }
	return value
}

pub fn (arena &Arena) floating(reference Ref) !f64 {
	arena.require_live()!
	value := arena.api.as_float(reference)
	if arena.api.error_occurred() != unsafe { nil } { return arena.api.exception() }
	return value
}

pub fn (arena &Arena) string(reference Ref) !string {
	arena.require_live()!
	mut length := isize(0)
	data := arena.api.unicode_data(reference, &length)
	if data == unsafe { nil } { return arena.api.exception() }
	if length < 0 || length > 64 * 1024 * 1024 { return error('CPython text exceeds 64 MiB') }
	return unsafe { tos(&u8(data), int(length)).clone() }
}

pub fn (arena &Arena) bytes(reference Ref) ![]u8 {
	arena.require_live()!
	mut length := isize(0)
	mut data := &char(unsafe { nil })
	if arena.api.bytes_data(reference, &data, &length) != 0 { return arena.api.exception() }
	if length < 0 || length > 64 * 1024 * 1024 { return error('CPython bytes exceed 64 MiB') }
	mut result := []u8{len: int(length)}
	if length > 0 {
		if data == unsafe { nil } { return error('CPython returned absent bytes') }
		unsafe { vmemcpy(result.data, data, int(length)) }
	}
	return result
}

pub fn (arena &Arena) length(reference Ref) !int {
	arena.require_live()!
	value := arena.api.size(reference)
	if value < 0 { return arena.api.exception() }
	if value > 0x7fffffff { return error('CPython sequence exceeds V index range') }
	return int(value)
}

pub fn (arena &Arena) truth(reference Ref) !bool {
	arena.require_live()!
	value := arena.api.truth(reference)
	if value < 0 { return arena.api.exception() }
	return value != 0
}

pub fn (arena &Arena) equal(left Ref, right Ref) !bool {
	arena.require_live()!
	value := arena.api.compare(left, right, 2) // Py_EQ
	if value < 0 { return arena.api.exception() }
	return value != 0
}

fn (arena &Arena) require_live() ! {
	if arena.closed { return error('CPython arena is retired') }
}
