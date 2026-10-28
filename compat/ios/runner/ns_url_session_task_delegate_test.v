// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.object_getClass(voidptr) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.method_getImplementation(voidptr) voidptr
fn C.dlsym(voidptr, &char) voidptr
type TaskDelegateSend = fn (u64, u64, u64, u64, u64) u64
type TaskDelegateWeak = fn (&u64, u64) u64
type TaskDelegateWeakDestroy = fn (&u64)
struct TaskDelegateApi { native bool send u64 }
fn (a TaskDelegateApi) cls(name &char) u64 {
	$if macos { if a.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[ctext(u64(name))]
}
fn (a TaskDelegateApi) sel(name &char) u64 {
	$if macos { if a.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (a TaskDelegateApi) msg(object u64, name &char, x u64, y u64, z u64) u64 {
	return unsafe { TaskDelegateSend(voidptr(a.send))(object, a.sel(name), x, y, z) }
}
fn (a TaskDelegateApi) pool() u64 {
	return if a.native { a.msg(a.cls(c'NSAutoreleasePool'), c'new', 0, 0, 0) } else { objc_pool_push() }
}
fn (a TaskDelegateApi) drain(pool u64) {
	if a.native { a.msg(pool, c'drain', 0, 0, 0) } else { objc_pool_pop(pool) }
}
fn (a TaskDelegateApi) release(object u64) { a.msg(object, c'release', 0, 0, 0) }
fn (a TaskDelegateApi) weak(location &u64, object u64) {
	$if macos { if a.native {
		unsafe { TaskDelegateWeak(C.dlsym(voidptr(i64(-2)), c'objc_storeWeak'))(location, object) }; return
	} }
	objc_store_weak(location, object)
}
fn (a TaskDelegateApi) destroy_weak(location &u64) {
	$if macos { if a.native {
		unsafe { TaskDelegateWeakDestroy(C.dlsym(voidptr(i64(-2)), c'objc_destroyWeak'))(location) }; return
	} }
	objc_destroy_weak(location)
}
fn (a TaskDelegateApi) imp(object u64, name &char, types string) u64 {
	selector := a.sel(name)
	assert a.msg(object, c'respondsToSelector:', selector, 0, 0) == 1
	$if macos { if a.native {
		method := C.class_getInstanceMethod(C.object_getClass(voidptr(object)), voidptr(selector))
		assert method != unsafe { nil } && ctext(u64(C.method_getTypeEncoding(method))) == types
		return u64(C.method_getImplementation(method))
	} }
	method := objc_instance_method(read64(object), selector)
	assert method != 0 && ctext(u64(objc_method_types(method))) == types
	return objc_method_imp(method)
}
fn task_delegate_worker(a TaskDelegateApi, task u64, left u64, right u64, offset int) {
	pool := a.pool()
	for index in 0 .. 128 {
		a.msg(task, c'setDelegate:', if (index + offset) & 1 == 0 { left } else { right }, 0, 0)
		assert a.msg(task, c'delegate', 0, 0, 0) in [left, right]!
	}
	a.drain(pool)
}
fn task_delegate_cases(a TaskDelegateApi, task u64) {
	assert a.msg(task, c'delegate', 0, 0, 0) == 0
	get := a.imp(task, c'delegate', '@16@0:8')
	set := a.imp(task, c'setDelegate:', 'v24@0:8@16')
	for keep_getter in [false, true]! {
		pool := a.pool()
		delegate := a.msg(a.cls(c'NSObject'), c'new', 0, 0, 0)
		mut weak := u64(0); a.weak(unsafe { &weak }, delegate)
		unsafe { TaskDelegateSend(voidptr(set))(task, a.sel(c'setDelegate:'), delegate, 0, 0) }
		a.release(delegate); assert weak == delegate
		// Reassigning the same retained object must acquire it before retiring it.
		a.msg(task, c'setDelegate:', delegate, 0, 0); assert weak == delegate
		if keep_getter {
			assert unsafe { TaskDelegateSend(voidptr(get))(task, a.sel(c'delegate'), 0, 0, 0) } == delegate
		}
		a.msg(task, c'setDelegate:', 0, 0, 0)
		assert (weak != 0) == keep_getter
		a.drain(pool); assert weak == 0; a.destroy_weak(unsafe { &weak })
	}
	pool := a.pool()
	left := a.msg(a.cls(c'NSObject'), c'new', 0, 0, 0)
	right := a.msg(a.cls(c'NSObject'), c'new', 0, 0, 0)
	mut workers := []thread{}
	for index in 0 .. 8 { workers << spawn task_delegate_worker(a, task, left, right, index) }
	workers.wait(); unsafe { workers.free() }
	a.msg(task, c'setDelegate:', 0, 0, 0)
	a.release(left); a.release(right); a.drain(pool)
}
fn task_delegate_shared(a TaskDelegateApi) {
	outer := a.pool()
	for name in [c'NSURLSessionTask', c'NSURLSessionDownloadTask', c'NSURLSessionDataTask', c'NSURLSessionUploadTask']! {
		task := a.msg(a.cls(name), c'new', 0, 0, 0)
		assert a.msg(a.cls(name), c'respondsToSelector:', a.sel(c'setDelegate:'), 0, 0) == 0
		task_delegate_cases(a, task)
		delegate := a.msg(a.cls(c'NSObject'), c'new', 0, 0, 0)
		mut weak := u64(0); a.weak(unsafe { &weak }, delegate)
		a.msg(task, c'setDelegate:', delegate, 0, 0); a.release(delegate)
		a.release(task); assert weak == 0; a.destroy_weak(unsafe { &weak })
	}
	config := a.msg(a.cls(c'NSURLSessionConfiguration'), c'defaultSessionConfiguration', 0, 0, 0)
	session_delegate := a.msg(a.cls(c'NSObject'), c'new', 0, 0, 0)
	session := a.msg(a.msg(a.cls(c'NSURLSession'), c'sessionWithConfiguration:delegate:delegateQueue:', config, session_delegate, 0), c'retain', 0, 0, 0)
	url := a.msg(a.cls(c'NSURL'), c'fileURLWithPath:', a.msg(a.cls(c'NSString'), c'stringWithUTF8String:', u64(c'/vinix/no-transfer'), 0, 0), 0, 0)
	request := a.msg(a.cls(c'NSURLRequest'), c'requestWithURL:', url, 0, 0)
	task := a.msg(session, c'dataTaskWithRequest:', request, 0, 0)
	task_delegate_cases(a, task)
	assert a.msg(session, c'delegate', 0, 0, 0) == session_delegate
	assert a.msg(task, c'state', 0, 0, 0) == 1
	if a.native { a.msg(session, c'invalidateAndCancel', 0, 0, 0) }
	a.release(session_delegate); a.release(session); a.drain(outer)
}
fn test_task_delegate_native() {
	$if macos {
		task_delegate_shared(TaskDelegateApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))})
		println('IOS-TASK-DELEGATE-NATIVE: four base classes, suspended data task, independent retained delegate, nil/replacement/self assignment, getter lifetime, metadata, IMP and eight workers PASS')
	}
}
__global task_delegate_reentrant_task = u64(0)
__global task_delegate_destructors = 0
fn task_delegate_reentrant_worker() {
	pool := objc_pool_push()
	api := TaskDelegateApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
	assert api.msg(task_delegate_reentrant_task, c'delegate', 0, 0, 0) == 0
	api.msg(task_delegate_reentrant_task, c'setTaskDescription:', objc_autorelease(owned_string('retired outside lock')), 0, 0)
	objc_pool_pop(pool)
}
fn task_delegate_destructor(object u64, selector &char) {
	worker := spawn task_delegate_reentrant_worker(); worker.wait()
	task_delegate_destructors++
}
fn test_task_delegate_runtime() {
	a := TaskDelegateApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
	for _ in 0 .. 2 {
		objc_start(); task_delegate_shared(a); assert ios_runtime.live == 0
		assert objc_instance_method(a.cls(c'NSObject'), u64(c'setDelegate:')) == 0
		delegate_cls := objc_allocate_class(a.cls(c'NSObject'), c'VinixTaskDelegate', 0)
		assert objc_add_method(delegate_cls, u64(c'.cxx_destruct'), u64(unsafe { voidptr(task_delegate_destructor) }), c'v16@0:8')
		objc_register_class(delegate_cls)
		task_delegate_reentrant_task = objc_new(a.cls(c'NSURLSessionTask'))
		input_pool := objc_pool_push()
		a.msg(task_delegate_reentrant_task, c'setDelegate:', objc_autorelease(objc_new(delegate_cls)), 0, 0)
		// Drop the autorelease before replacing so retirement invokes the destructor.
		objc_pool_pop(input_pool)
		task_delegate_destructors = 0
		a.msg(task_delegate_reentrant_task, c'setDelegate:', 0, 0, 0)
		assert task_delegate_destructors == 1
		a.release(task_delegate_reentrant_task)
		for changed_isa in [false, true]! {
			mut storage := [92]u64{}; storage[0] = 0x1122334455667788; storage[91] = 0x8877665544332211
			task := if changed_isa { objc_new(a.cls(c'NSURLSessionTask')) } else { objc_construct_instance(a.cls(c'NSURLSessionTask'), u64(unsafe { &storage[1] })) }
			delegate := objc_new(a.cls(c'NSObject')); mut weak := u64(0)
			a.weak(unsafe { &weak }, delegate); a.msg(task, c'setDelegate:', delegate, 0, 0); a.release(delegate)
			assert weak != 0
			if changed_isa { objc_set_class(task, a.cls(c'NSObject')); a.release(task) } else { assert objc_destruct_instance(task) == task }
			assert weak == 0 && storage[0] == 0x1122334455667788 && storage[91] == 0x8877665544332211
			a.destroy_weak(unsafe { &weak })
		}
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		task := objc_autorelease(objc_new(a.cls(c'NSURLSessionDataTask')))
		delegate := objc_new(a.cls(c'NSObject')); mut weak := u64(0)
		a.weak(unsafe { &weak }, delegate); a.msg(task, c'setDelegate:', delegate, 0, 0); a.release(delegate)
		objc_stop(); assert weak == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-TASK-DELEGATE: native shared cases, scope, concurrent replacement, reentrant retirement, guarded caller storage, isa replacement and two balanced lifetimes PASS')
}
