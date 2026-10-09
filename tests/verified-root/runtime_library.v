// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidhost as ah
import runtimeroot
import cpythonhost as cpython
import json2

#include <Python.h>

fn C.PyTuple_Size(voidptr) isize
fn C.PyTuple_GetItem(voidptr, isize) voidptr
fn C.Py_IncRef(voidptr)
fn C.PyErr_NoMemory() voidptr
fn C.GC_thread_is_registered() i32
fn C.GC_allow_register_threads()
fn C.GC_get_stack_base(voidptr) i32
fn C.GC_register_my_thread(voidptr) i32
fn C.GC_unregister_my_thread() i32

@[export: 'vinix_verified_root_helper']
fn helper(operation &char, namespace voidptr, arguments voidptr, syntax voidptr) voidptr {
	C.GC_allow_register_threads()
	mut registered := false
	if C.GC_thread_is_registered() == 0 {
		mut stack := C.GC_stack_base{}
		if C.GC_get_stack_base(&stack) != 0 { return C.PyErr_NoMemory() }
		registered = C.GC_register_my_thread(&stack) == 0
		if !registered { return C.PyErr_NoMemory() }
	}
	defer { if registered { C.GC_unregister_my_thread() } }
	mut context := cpython.begin(namespace, syntax)
	operation_name := unsafe { operation.vstring() }
	if operation_name !in ['command', 'device_blocks', 'enroll', 'tamper'] {
		return context.native_error('unsupported verified-root helper: ' + operation_name)
	}
	mut ids := []ah.Value{}
	for i in 0 .. int(C.PyTuple_Size(arguments)) {
		p := C.PyTuple_GetItem(arguments, i)
		C.Py_IncRef(p)
		ids << ah.Value(context.retain(p))
	}
	result := runtimeroot.dispatch({
		'operation': ah.Value(operation_name)
		'arguments': ah.Value(ids)
	}) or {
		if cpython.pending_error() { return context.native_error('') }
		if err is cpython.Failure {
			return context.finish(unsafe { nil }, int(ah.field(err.value, 'binding_error') as int))
		}
		return context.native_error(err.msg())
	}
	value := if result is json2.Null {
		cpython.none_result()
	} else {
		cpython.get_result(result.text())
	}
	return context.finish(value, -1)
}
