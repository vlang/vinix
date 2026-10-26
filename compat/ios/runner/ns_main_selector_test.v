// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

$if macos {
	#flag -framework Foundation
	#flag -framework CoreFoundation
	#include <objc/runtime.h>
	#define dispatch_sync vinix_native_header_dispatch_sync
	#include <CoreFoundation/CFRunLoop.h>
	#undef dispatch_sync
}
#include <dlfcn.h>

fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.class_addMethod(voidptr, voidptr, voidptr, &char) bool
fn C.class_addIvar(voidptr, &char, usize, u8, &char) bool
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.objc_storeWeak(&u64, voidptr) voidptr
fn C.CFRunLoopRunInMode(voidptr, f64, bool) i32

type MainSelectorSend = fn (u64, u64, u64, u64, u64) u64

struct MainSelectorApi {
	native bool
	send u64
}

fn (api MainSelectorApi) cls(name &char) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[ctext(u64(name))]
}

fn (api MainSelectorApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}

fn (api MainSelectorApi) msg(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { MainSelectorSend(voidptr(api.send))(object, api.sel(name), a, b, c) }
}

fn (api MainSelectorApi) perform(target u64, selector &char, argument u64, wait bool) {
	api.msg(target, c'performSelectorOnMainThread:withObject:waitUntilDone:', api.sel(selector), argument, u64(wait))
}

fn (api MainSelectorApi) release(object u64) { api.msg(object, c'release', 0, 0, 0) }

fn (api MainSelectorApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls(c'NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}

fn (api MainSelectorApi) pop(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}

fn (api MainSelectorApi) pump() {
	$if macos { if api.native {
		cell := C.dlsym(unsafe { voidptr(-2) }, c'kCFRunLoopDefaultMode')
		assert cell != unsafe { nil }
		C.CFRunLoopRunInMode(unsafe { voidptr(*(&u64(cell))) }, 0.001, false)
		return
	} }
	dispatch_main_drain()
}

fn (api MainSelectorApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { voidptr(object) }); return } }
	objc_store_weak(slot, object)
}

fn (api MainSelectorApi) clear_weak(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}

struct MainSelectorCapture {
mut:
	api MainSelectorApi
	main_thread u64
	argument u64
	count i64
	started i64
	returned i64
	nested bool
}

fn main_selector_load(slot &i64) i64 { return C.ios_ref_change(slot, 0) }

fn main_selector_callback(object u64, selector &char, argument u64) {
	_ = selector
	mut capture := unsafe { &MainSelectorCapture(read64(object + 8)) }
	assert u64(C.pthread_self()) == capture.main_thread
	assert argument == capture.argument
	if capture.nested {
		capture.nested = false
		before := main_selector_load(&capture.count)
		capture.api.perform(object, c'record:', argument, true)
		assert main_selector_load(&capture.count) == before + 1
	}
	C.ios_ref_change(unsafe { &capture.count }, 1)
}

fn main_selector_class(api MainSelectorApi) u64 {
	$if macos { if api.native {
		cls := C.objc_allocateClassPair(C.objc_getClass(c'NSObject'), c'VinixMainSelectorFixture', 0)
		assert cls != unsafe { nil }
		assert C.class_addIvar(cls, c'context', 8, 3, c'^v')
		assert C.class_addMethod(cls, C.sel_registerName(c'record:'), unsafe { voidptr(main_selector_callback) }, c'v24@0:8@16')
		C.objc_registerClassPair(cls)
		return u64(cls)
	} }
	cls := objc_allocate_class(api.cls(c'NSObject'), c'VinixMainSelectorFixture', 0)
	assert objc_add_ivar(cls, c'context', 8, 3, c'^v')
	assert objc_add_method(cls, u64(c'record:'), u64(unsafe { voidptr(main_selector_callback) }), c'v24@0:8@16')
	objc_register_class(cls)
	return cls
}

fn main_selector_target(api MainSelectorApi, cls u64, capture &MainSelectorCapture) u64 {
	object := api.msg(cls, c'new', 0, 0, 0)
	unsafe { *(&u64(object + 8)) = u64(capture) }
	return object
}

fn main_selector_worker(api MainSelectorApi, target u64, argument u64, wait bool, capture &MainSelectorCapture) {
	pool := api.pool()
	C.ios_ref_change(unsafe { &capture.started }, 1)
	api.perform(target, c'record:', argument, wait)
	if wait { assert main_selector_load(&capture.count) == 1 }
	api.release(target)
	api.release(argument)
	api.pop(pool)
	C.ios_ref_change(unsafe { &capture.returned }, 1)
}

fn main_selector_cases(api MainSelectorApi) {
	pool := api.pool()
	cls := main_selector_class(api)
	selector := api.sel(c'performSelectorOnMainThread:withObject:waitUntilDone:')
	mut types := ''
	$if macos { if api.native {
		types = ctext(u64(C.method_getTypeEncoding(C.class_getInstanceMethod(unsafe { voidptr(cls) }, unsafe { voidptr(selector) }))))
	} }
	if !api.native { types = ctext(u64(objc_method_types(objc_instance_method(cls, selector)))) }
	assert types == 'v36@0:8:16@24B32', types
	mut capture := &MainSelectorCapture{api: api, main_thread: u64(C.pthread_self())}
	target := main_selector_target(api, cls, capture)
	assert api.msg(target, c'respondsToSelector:', selector, 0, 0) == 1
	signature := api.msg(target, c'methodSignatureForSelector:', selector, 0, 0)
	assert api.msg(signature, c'numberOfArguments', 0, 0, 0) == 5
	api.perform(target, c'record:', 0, true)
	assert main_selector_load(&capture.count) == 1
	api.perform(target, c'record:', 0, false)
	assert main_selector_load(&capture.count) == 1
	deadline := time.sys_mono_now() + 10 * time.second
	for main_selector_load(&capture.count) != 2 { assert time.sys_mono_now() < deadline; api.pump() }
	capture.nested = true
	api.perform(target, c'record:', 0, false)
	for main_selector_load(&capture.count) != 4 { assert time.sys_mono_now() < deadline; api.pump() }
	api.release(target)
	// Exercise a built-in target, FIFO ordering and argument ownership.
	array := api.msg(api.cls(c'NSMutableArray'), c'new', 0, 0, 0)
	mut expected := [3]u64{}
	for i in 0 .. 3 {
		argument := api.msg(api.cls(c'NSObject'), c'new', 0, 0, 0)
		expected[i] = argument
		api.perform(array, c'addObject:', argument, false)
		api.release(argument)
	}
	assert api.msg(array, c'count', 0, 0, 0) == 0
	for api.msg(array, c'count', 0, 0, 0) != 3 { assert time.sys_mono_now() < deadline; api.pump() }
	for i, argument in expected { assert api.msg(array, c'objectAtIndex:', u64(i), 0, 0) == argument }
	api.release(array)
	for wait in [false, true]! {
		mut worker_capture := &MainSelectorCapture{api: api, main_thread: u64(C.pthread_self())}
		argument := api.msg(api.cls(c'NSObject'), c'new', 0, 0, 0)
		worker_capture.argument = argument
		worker_target := main_selector_target(api, cls, worker_capture)
		mut target_weak := u64(0)
		mut argument_weak := u64(0)
		api.weak(&target_weak, worker_target)
		api.weak(&argument_weak, argument)
		worker := spawn main_selector_worker(api, worker_target, argument, wait, worker_capture)
		for main_selector_load(&worker_capture.started) == 0 { assert time.sys_mono_now() < deadline; time.sleep(time.millisecond) }
		if wait {
			time.sleep(10 * time.millisecond)
			assert main_selector_load(&worker_capture.returned) == 0
		} else {
			for main_selector_load(&worker_capture.returned) == 0 { assert time.sys_mono_now() < deadline; time.sleep(time.millisecond) }
		}
		assert main_selector_load(&worker_capture.count) == 0
		assert target_weak != 0 && argument_weak != 0
		for main_selector_load(&worker_capture.returned) == 0 || main_selector_load(&worker_capture.count) != 1 {
			assert time.sys_mono_now() < deadline
			api.pump()
		}
		worker.wait()
		for target_weak != 0 || argument_weak != 0 { assert time.sys_mono_now() < deadline; api.pump() }
		api.clear_weak(&target_weak)
		api.clear_weak(&argument_weak)
		unsafe { free(worker_capture) }
	}
	unsafe { free(capture) }
	api.pop(pool)
}

fn test_main_selector_native_reference() {
	$if macos {
		api := MainSelectorApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		main_selector_cases(api)
		println('IOS-MAIN-SELECTOR-NATIVE: metadata, inline/deferred/nested execution, worker wait, ownership and built-in target PASS')
	}
}

fn test_main_selector_runtime_and_shutdown() ! {
	for _ in 0 .. 2 {
		objc_start()
		system_data_start()!
		api := MainSelectorApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) })}
		main_selector_cases(api)
		mut capture := MainSelectorCapture{api: api, main_thread: u64(C.pthread_self())}
		target := main_selector_target(api, api.cls(c'VinixMainSelectorFixture'), &capture)
		argument := objc_new(api.cls(c'NSObject'))
		mut target_weak := u64(0)
		mut argument_weak := u64(0)
		objc_store_weak(&target_weak, target)
		objc_store_weak(&argument_weak, argument)
		api.perform(target, c'record:', argument, false)
		objc_release(target)
		objc_release(argument)
		assert target_weak != 0 && argument_weak != 0
		// Stop cancels pending asynchronous work without calling application code.
		dispatch_stop()
		assert main_selector_load(&capture.count) == 0 && target_weak == 0 && argument_weak == 0
		objc_destroy_weak(&target_weak)
		objc_destroy_weak(&argument_weak)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		system_data_stop()
		assert dispatch_runtime == unsafe { nil }
	}
	println('IOS-MAIN-SELECTOR: shared native cases, cancellation ownership and two clean runtime cycles PASS')
}
