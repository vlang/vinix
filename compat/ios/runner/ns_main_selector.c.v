// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct FoundationMainSelector {
	target   u64
	selector u64
	argument u64
}

fn ns_main_selector_run(pointer voidptr) {
	call := unsafe { &FoundationMainSelector(pointer) }
	// Resolve at execution time, including inherited and built-in methods.
	imp := objc_method_implementation(objc_object_class(call.target), call.selector)
	unsafe { ObjAction(voidptr(imp))(call.target, &char(call.selector), call.argument) }
}

fn ns_main_selector_free(pointer voidptr) {
	call := unsafe { &FoundationMainSelector(pointer) }
	objc_release(call.target)
	objc_release(call.argument)
	C.free(pointer)
}

fn ns_main_selector(target u64, selector u64, argument u64, wait bool) {
	if selector == 0 { panic('iOS: main-thread perform requires a selector') }
	call := &FoundationMainSelector{
		target: objc_retain(target)
		selector: selector
		argument: objc_retain(argument)
	}
	if wait && u64(C.pthread_self()) == ios_runtime.main_thread {
		// Foundation executes this case inline, even from a main-queue callback.
		ns_main_selector_run(call)
		ns_main_selector_free(call)
	} else if wait {
		dispatch_sync(darwin_dispatch_get_main_queue(), 0, call, ns_main_selector_run)
		ns_main_selector_free(call)
	} else {
		// The desktop's main-thread drain owns pending calls through execution
		// or shutdown cancellation, just as it owns other framework work.
		dispatch_submit_owned(darwin_dispatch_get_main_queue(), call, ns_main_selector_run,
			ns_main_selector_free)
	}
}
