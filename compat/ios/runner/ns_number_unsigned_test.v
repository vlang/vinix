// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.method_getImplementation(voidptr) voidptr
fn C.dlsym(voidptr, &char) voidptr

type NumberUnsignedSend = fn (u64, u64, u64, u64) u64
type NumberUnsignedReal = fn (u64, u64) f64
struct NumberUnsignedApi { native bool send u64 }
fn (api NumberUnsignedApi) cls(name &char) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[unsafe { name.vstring() }]
}
fn (api NumberUnsignedApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api NumberUnsignedApi) message(object u64, name &char, value u64) u64 {
	return unsafe { NumberUnsignedSend(voidptr(api.send))(object, api.sel(name), value, 0) }
}
fn (api NumberUnsignedApi) pool() u64 {
	$if macos { if api.native { return api.message(api.cls(c'NSAutoreleasePool'), c'new', 0) } }
	return objc_pool_push()
}
fn (api NumberUnsignedApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0); return } }
	objc_pool_pop(pool)
}
fn number_unsigned_worker(api NumberUnsignedApi, cls u64, imp u64, seed u64) {
	for index in 0 .. 128 {
		pool := api.pool()
		value := seed + u64(index)
		object := unsafe { NumberUnsignedSend(voidptr(imp))(cls, api.sel(c'numberWithUnsignedLong:'), value, 0) }
		assert object != 0 && api.message(object, c'unsignedIntegerValue', 0) == value
		api.message(object, c'retain', 0)
		api.drain(pool)
		assert api.message(object, c'unsignedIntegerValue', 0) == value
		api.message(object, c'release', 0)
	}
}
fn number_unsigned_shared(api NumberUnsignedApi) {
	cls := api.cls(c'NSNumber')
	selector := api.sel(c'numberWithUnsignedLong:')
	mut imp := u64(0)
	$if macos { if api.native {
		method := C.class_getClassMethod(voidptr(cls), voidptr(selector))
		assert method != unsafe { nil }
		assert unsafe { C.method_getTypeEncoding(method).vstring() } == '@24@0:8Q16'
		assert C.class_getInstanceMethod(voidptr(cls), voidptr(selector)) == unsafe { nil }
		imp = u64(C.method_getImplementation(method))
	} }
	if !api.native {
		method := objc_class_method(cls, selector)
		assert method != 0 && ctext(u64(objc_method_types(method))) == '@24@0:8Q16'
		assert objc_instance_method(cls, selector) == 0
		assert objc_class_method(api.cls(c'NSObject'), selector) == 0
		imp = objc_method_imp(method)
	}
	assert imp != 0 && api.message(cls, c'respondsToSelector:', selector) == 1
	mut threads := []thread{}
	for index in 0 .. 8 { threads << spawn number_unsigned_worker(api, cls, imp, u64(index) << 61) }
	threads.wait()
	pool := api.pool()
	for value in [u64(0), 1, 127, 128, 255, 256, 32767, 32768, 0x7fffffff, 0x80000000,
		0x1fffffffffffff, 0x20000000000000, 0x20000000000001,
		0x7fffffffffffffff, 0x8000000000000000, 0xfffffffffffffffe, 0xffffffffffffffff]! {
		object := api.message(cls, c'numberWithUnsignedLong:', value)
		direct := unsafe { NumberUnsignedSend(voidptr(imp))(cls, selector, value, 0) }
		assert object != 0 && direct != 0
		assert api.message(object, c'unsignedIntegerValue', 0) == value
		assert api.message(object, c'integerValue', 0) == value
		assert api.message(object, c'boolValue', 0) == u64(value != 0)
		assert ctext(api.message(object, c'objCType', 0)) == if value <= u64(9223372036854775807) { 'q' } else { 'Q' }
		text := api.message(object, c'stringValue', 0)
		assert ctext(api.message(text, c'UTF8String', 0)) == value.str()
		assert unsafe { NumberUnsignedReal(voidptr(api.send))(object, api.sel(c'doubleValue')) } == f64(value)
		mut bytes := [u64(0xaaaaaaaaaaaaaaaa), 0x5555555555555555]!
		api.message(object, c'getValue:', u64(unsafe { &bytes[0] }))
		assert bytes[0] == value && bytes[1] == 0x5555555555555555
		bytes[0] = ~value
		unsafe { NumberUnsignedSend(voidptr(api.send))(object, api.sel(c'getValue:size:'), u64(&bytes[0]), 8) }
		assert bytes[0] == value && bytes[1] == 0x5555555555555555
		assert api.message(object, c'isEqual:', direct) == 1
		assert api.message(object, c'isEqual:', 0) == 0
		signed := api.message(cls, c'numberWithInteger:', value)
		assert api.message(object, c'isEqual:', signed) == u64(value <= u64(9223372036854775807))
		copy := api.message(object, c'copy', 0)
		assert copy == object
		api.message(copy, c'release', 0)
	}
	signature := api.message(cls, c'methodSignatureForSelector:', selector)
	assert signature != 0 && api.message(signature, c'numberOfArguments', 0) == 3
	assert api.message(signature, c'methodReturnLength', 0) == 8
	assert ctext(api.message(signature, c'getArgumentTypeAtIndex:', 2)) == 'Q'
	assert api.message(api.cls(c'NSObject'), c'respondsToSelector:', selector) == 0
	api.drain(pool)
}
fn test_number_unsigned_native() {
	$if macos {
		api := NumberUnsignedApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		number_unsigned_shared(api)
		println('IOS-NUMBER-UNSIGNED-NATIVE: full range, metadata, IMP, storage, values, equality, ownership and eight workers PASS')
	}
}
fn test_number_unsigned_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		number_unsigned_shared(NumberUnsignedApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })})
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-NUMBER-UNSIGNED: full range, metadata, IMP, storage, values, equality, ownership, eight workers and two balanced lifetimes PASS')
}
