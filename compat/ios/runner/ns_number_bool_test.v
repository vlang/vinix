// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#flag -framework CoreFoundation
	#include <objc/runtime.h>
	#include <CoreFoundation/CFNumber.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.method_getImplementation(voidptr) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFGetTypeID(voidptr) u64
fn C.CFBooleanGetTypeID() u64
fn C.CFBooleanGetValue(voidptr) bool

type NumberBoolSend = fn (u64, u64, u64) u64
struct NumberBoolApi { native bool send u64 }
fn (api NumberBoolApi) cls(name &char) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[unsafe { name.vstring() }]
}
fn (api NumberBoolApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api NumberBoolApi) message(object u64, name &char, value u64) u64 {
	return unsafe { NumberBoolSend(voidptr(api.send))(object, api.sel(name), value) }
}
fn (api NumberBoolApi) pool() u64 {
	$if macos { if api.native { return api.message(api.cls(c'NSAutoreleasePool'), c'new', 0) } }
	return objc_pool_push()
}
fn (api NumberBoolApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0); return } }
	objc_pool_pop(pool)
}
fn number_bool_worker(api NumberBoolApi, cls u64, imp u64) {
	for index in 0 .. 128 {
		pool := api.pool()
		expected := u64(index & 1)
		object := api.message(cls, c'numberWithBool:', expected)
		direct := unsafe { NumberBoolSend(voidptr(imp))(cls, api.sel(c'numberWithBool:'), expected) }
		assert object != 0 && direct == object
		assert api.message(object, c'boolValue', 0) == expected
		api.message(object, c'retain', 0)
		api.drain(pool)
		assert api.message(object, c'integerValue', 0) == expected
		api.message(object, c'release', 0)
	}
}
fn number_bool_shared(api NumberBoolApi) {
	cls := api.cls(c'NSNumber')
	selector := api.sel(c'numberWithBool:')
	mut imp := u64(0)
	$if macos { if api.native {
		method := C.class_getClassMethod(voidptr(cls), voidptr(selector))
		assert method != unsafe { nil }
		assert unsafe { C.method_getTypeEncoding(method).vstring() } == '@20@0:8B16'
		assert C.class_getInstanceMethod(voidptr(cls), voidptr(selector)) == unsafe { nil }
		imp = u64(C.method_getImplementation(method))
	} }
	if !api.native {
		method := objc_class_method(cls, selector)
		assert method != 0 && ctext(u64(objc_method_types(method))) == '@20@0:8B16'
		assert objc_instance_method(cls, selector) == 0
		assert objc_class_method(api.cls(c'NSObject'), selector) == 0
		imp = objc_method_imp(method)
	}
	assert imp != 0 && api.message(cls, c'respondsToSelector:', selector) == 1
	// Race first construction, then check cache ownership after all worker pools drain.
	mut threads := []thread{}
	for _ in 0 .. 8 { threads << spawn number_bool_worker(api, cls, imp) }
	threads.wait()
	pool := api.pool()
	mut booleans := [2]u64{}
	for argument in [u64(0), 1, 2, 0xff, 0x100, 0x101, 0x100000000, 0x100000001, 0xffffffffffff0000, 0xffffffffffff0001]! {
		expected := u64(u32(argument) != 0)
		object := api.message(cls, c'numberWithBool:', argument)
		assert object != 0
		if booleans[expected] == 0 { booleans[expected] = object }
		assert object == booleans[expected]
		assert unsafe { NumberBoolSend(voidptr(imp))(cls, selector, argument) } == object
		assert api.message(object, c'boolValue', 0) == expected
		assert api.message(object, c'integerValue', 0) == expected
		assert ctext(api.message(object, c'objCType', 0)) == 'c'
		text := api.message(object, c'stringValue', 0)
		assert ctext(api.message(text, c'UTF8String', 0)) == if expected == 0 { '0' } else { '1' }
		mut bytes := [u8(0xa5), 0xa5]!
		api.message(object, c'getValue:', u64(unsafe { &bytes[0] }))
		assert bytes[0] == u8(expected) && bytes[1] == 0xa5
		assert api.message(object, c'copy', 0) == object
		api.message(object, c'release', 0)
		$if macos { if api.native {
			assert C.CFGetTypeID(voidptr(object)) == C.CFBooleanGetTypeID()
			assert C.CFBooleanGetValue(voidptr(object)) == (expected != 0)
			cell := C.dlsym(unsafe { voidptr(-2) }, if expected != 0 { c'kCFBooleanTrue' } else { c'kCFBooleanFalse' })
			assert cell != unsafe { nil } && read64(u64(cell)) == object
		} }
		if !api.native {
			assert cf_type_id(object) == cf_boolean_id()
			assert cf_boolean_value(object) == (expected != 0)
			assert framework_object(if expected != 0 { '_kCFBooleanTrue' } else { '_kCFBooleanFalse' }) == object
		}
	}
	assert booleans[0] != booleans[1]
	assert api.message(booleans[0], c'isEqual:', booleans[1]) == 0
	for expected in 0 .. 2 {
		number := api.message(cls, c'numberWithInteger:', u64(expected))
		assert api.message(booleans[expected], c'isEqual:', number) == 1
	}
	signature := api.message(cls, c'methodSignatureForSelector:', selector)
	assert signature != 0 && api.message(signature, c'numberOfArguments', 0) == 3
	assert api.message(signature, c'methodReturnLength', 0) == 8
	assert ctext(api.message(signature, c'getArgumentTypeAtIndex:', 2)) == 'B'
	api.drain(pool)
	assert api.message(booleans[0], c'boolValue', 0) == 0
	assert api.message(booleans[1], c'boolValue', 0) == 1
}
fn test_number_bool_native() {
	$if macos {
		api := NumberBoolApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		number_bool_shared(api)
		println('IOS-NUMBER-BOOL-NATIVE: normalization, metadata, IMP, CF identity, values, ownership and eight workers PASS')
	}
}
fn test_number_bool_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		number_bool_shared(NumberBoolApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })})
		assert ios_runtime.live == 2 && ios_runtime.objects.len == 2
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-NUMBER-BOOL: normalization, metadata, IMP, CF identity, values, ownership, eight workers and two balanced lifetimes PASS')
}
