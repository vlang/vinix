// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.object_getClass(voidptr) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.method_getImplementation(voidptr) voidptr
fn C.dlsym(voidptr, &char) voidptr

type NumberLongSend = fn (u64, u64, u64) u64
type NumberLongDouble = fn (u64, u64, f64) u64
struct NumberLongApi { native bool send u64 }
fn (a NumberLongApi) cls(name &char) u64 {
	$if macos { if a.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[unsafe { name.vstring() }]
}
fn (a NumberLongApi) sel(name &char) u64 {
	$if macos { if a.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (a NumberLongApi) msg(object u64, name &char, value u64) u64 {
	return unsafe { NumberLongSend(voidptr(a.send))(object, a.sel(name), value) }
}
fn (a NumberLongApi) real(value f64) u64 {
	$if macos { if a.native { return unsafe { NumberLongDouble(voidptr(a.send))(a.cls(c'NSNumber'), a.sel(c'numberWithDouble:'), value) } } }
	// Exercise the double representation used by JSON/CFNumber. Its public
	// NSNumber factory is outside this getter's compatibility scope.
	object := objc_allocate(a.cls(c'NSNumber'))
	mut header := obj_header(object)
	header.is_real = true
	header.real_number = value
	return objc_autorelease(object)
}
fn (a NumberLongApi) check(object u64, expected i64) u64 {
	selector := a.sel(c'longLongValue')
	assert object != 0 && a.msg(object, c'respondsToSelector:', selector) == 1
	mut imp := u64(0)
	$if macos { if a.native {
		method := C.class_getInstanceMethod(C.object_getClass(voidptr(object)), voidptr(selector))
		assert method != unsafe { nil }
		assert unsafe { C.method_getTypeEncoding(method).vstring() } == 'q16@0:8'
		imp = u64(C.method_getImplementation(method))
	} }
	if !a.native {
		method := objc_instance_method(read64(object), selector)
		assert method != 0 && ctext(u64(objc_method_types(method))) == 'q16@0:8'
		imp = objc_method_imp(method)
	}
	assert imp != 0 && i64(a.msg(object, c'longLongValue', 0)) == expected
	assert i64(unsafe { NumberLongSend(voidptr(imp))(object, selector, 0) }) == expected
	return imp
}
fn number_long_worker(a NumberLongApi, object u64, imp u64, expected i64) {
	for _ in 0 .. 256 {
		assert i64(a.msg(object, c'longLongValue', 0)) == expected
		assert i64(unsafe { NumberLongSend(voidptr(imp))(object, a.sel(c'longLongValue'), 0) }) == expected
	}
}
fn number_long_shared(a NumberLongApi) {
	pool := if a.native { a.msg(a.cls(c'NSAutoreleasePool'), c'new', 0) } else { objc_pool_push() }
	cls := a.cls(c'NSNumber')
	selector := a.sel(c'longLongValue')
	assert a.msg(cls, c'respondsToSelector:', selector) == 0
	$if macos { if a.native {
		assert C.class_getClassMethod(voidptr(cls), voidptr(selector)) == unsafe { nil }
	} }
	if !a.native {
		assert objc_class_method(cls, selector) == 0
		assert objc_instance_method(a.cls(c'NSObject'), selector) == 0
		assert objc_instance_method(a.cls(c'NSValue'), selector) == 0
	}
	for bits in [u64(0), 1, 127, 128, 0x7fffffff, 0x80000000, 0x1fffffffffffff,
		0x20000000000001, 0x7fffffffffffffff, 0x8000000000000000, 0xfffffffffffffffe, 0xffffffffffffffff]! {
		for factory in [c'numberWithInteger:', c'numberWithUnsignedLong:']! {
			a.check(a.msg(cls, factory, bits), i64(bits))
		}
	}
	for bits in [u64(0), 1, 2, 0x100000000, 0x100000001]! {
		a.check(a.msg(cls, c'numberWithBool:', bits), i64(u32(bits) != 0))
	}
	values := [f64(0), -0.0, 1.99, -1.99, 9007199254740991.0, -9007199254740991.0,
		9223372036854774784.0, 9223372036854775808.0, -9223372036854775808.0,
		-9223372036854777856.0, math.inf(1), math.inf(-1), math.nan()]
	expected := [i64(0), 0, 1, -1, 9007199254740991, -9007199254740991,
		9223372036854774784, 9223372036854775807, i64(-9223372036854775807) - 1,
		i64(-9223372036854775807) - 1, 9223372036854775807, i64(-9223372036854775807) - 1, 0]
	for i, value in values { a.check(a.real(value), expected[i]) }
	object := a.msg(cls, c'numberWithUnsignedLong:', 0x8000000000000001)
	imp := a.check(object, i64(0x8000000000000001))
	signature := a.msg(object, c'methodSignatureForSelector:', selector)
	assert signature != 0 && a.msg(signature, c'numberOfArguments', 0) == 2
	assert a.msg(signature, c'methodReturnLength', 0) == 8
	assert ctext(a.msg(signature, c'methodReturnType', 0)) == 'q'
	assert ctext(a.msg(signature, c'getArgumentTypeAtIndex:', 0)) == '@'
	assert ctext(a.msg(signature, c'getArgumentTypeAtIndex:', 1)) == ':'
	a.msg(object, c'retain', 0)
	if a.native { a.msg(pool, c'drain', 0) } else { objc_pool_pop(pool) }
	mut threads := []thread{}
	for _ in 0 .. 8 { threads << spawn number_long_worker(a, object, imp, i64(0x8000000000000001)) }
	threads.wait()
	a.check(object, i64(0x8000000000000001))
	a.msg(object, c'release', 0)
}
fn test_number_long_native() {
	$if macos {
		number_long_shared(NumberLongApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))})
		println('IOS-NUMBER-LONG-LONG-NATIVE: integer bits, booleans, fractional values, saturation, NaN, metadata, IMP, signature, ownership and eight workers PASS')
	}
}
fn test_number_long_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		number_long_shared(NumberLongApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })})
		assert ios_runtime.live == 2 && ios_runtime.objects.len == 2
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-NUMBER-LONG-LONG: integer bits, booleans, fractional values, saturation, NaN, metadata, IMP, signature, ownership, eight workers and two balanced lifetimes PASS')
}
