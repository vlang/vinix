module main

import cpythonhost

fn C.GC_thread_is_registered() i32
fn C.GC_allow_register_threads()
fn C.GC_get_stack_base(voidptr) i32
fn C.GC_register_my_thread(voidptr) i32
fn C.GC_unregister_my_thread() i32
fn C.PyErr_NoMemory() voidptr

@[export: 'vinix_kernel_gap_core']
fn entry(operation &char, namespace voidptr, arguments voidptr, syntax voidptr) voidptr {
	C.GC_allow_register_threads()
	mut registered := false
	if C.GC_thread_is_registered() == 0 {
		mut stack := C.GC_stack_base{}
		if C.GC_get_stack_base(&stack) != 0 { return C.PyErr_NoMemory() }
		registered = C.GC_register_my_thread(&stack) == 0
		if !registered { return C.PyErr_NoMemory() }
	}
	defer { if registered { C.GC_unregister_my_thread() } }
	return cpythonhost.gap_library_entry(operation, namespace, arguments, syntax)
}
