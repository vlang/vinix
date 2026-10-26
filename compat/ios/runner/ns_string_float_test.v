// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math
import macho
import stringfloatcases

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.method_getImplementation(voidptr) voidptr
fn C.dlsym(voidptr, &char) voidptr

type StringFloatSend = fn (u64, u64, u64, u64, u64) u64
type StringFloatReturn = fn (u64, u64) f32
struct StringFloatApi { native bool send u64 }

fn (api StringFloatApi) cls(name &char) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[unsafe { name.vstring() }]
}
fn (api StringFloatApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api StringFloatApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { StringFloatSend(voidptr(api.send))(object, api.sel(name), a, b, c) }
}
fn (api StringFloatApi) pool() u64 {
	$if macos { if api.native { return api.message(api.cls(c'NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api StringFloatApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api StringFloatApi) check(object u64, imp u64, expected u32) {
	assert object != 0
	selector := api.sel(c'floatValue')
	assert math.f32_bits(unsafe { StringFloatReturn(voidptr(api.send))(object, selector) }) == expected
	assert math.f32_bits(unsafe { StringFloatReturn(voidptr(imp))(object, selector) }) == expected
}
fn string_float_worker(api StringFloatApi, cls u64, imp u64) {
	pool := api.pool()
	for _ in 0 .. 128 {
		text := '-١٢.٥e٢tail'
		object := api.message(api.message(cls, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(text.str), u64(text.len), 4)
		api.check(object, imp, 0xc49c4000)
		api.message(object, c'release', 0, 0, 0)
	}
	api.drain(pool)
}
fn string_float_shared(api StringFloatApi) {
	pool := api.pool()
	for name in [c'NSString', c'NSMutableString']! {
		cls := api.cls(name)
		selector := api.sel(c'floatValue')
		mut imp := u64(0)
		$if macos { if api.native {
			method := C.class_getInstanceMethod(voidptr(cls), voidptr(selector))
			assert method != unsafe { nil }
			assert unsafe { C.method_getTypeEncoding(method).vstring() } == 'f16@0:8'
			imp = u64(C.method_getImplementation(method))
		} }
		if !api.native {
			method := objc_instance_method(cls, selector)
			assert method != 0 && ctext(u64(objc_method_types(method))) == 'f16@0:8'
			assert objc_instance_method(read64(cls), selector) == 0
			imp = objc_method_imp(method)
		}
		assert imp != 0 && api.message(cls, c'respondsToSelector:', selector, 0, 0) == 0
		for item in stringfloatcases.cases() {
			object := api.message(api.message(cls, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(item.input.str), u64(item.input.len), 4)
			assert api.message(object, c'respondsToSelector:', selector, 0, 0) == 1
			api.check(object, imp, item.bits)
			api.message(object, c'release', 0, 0, 0)
		}
		object := api.message(api.message(cls, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(c'1.5'), 3, 4)
		signature := api.message(object, c'methodSignatureForSelector:', selector, 0, 0)
		assert signature != 0 && api.message(signature, c'numberOfArguments', 0, 0, 0) == 2
		assert api.message(signature, c'methodReturnLength', 0, 0, 0) == 4
		assert ctext(api.message(signature, c'methodReturnType', 0, 0, 0)) == 'f'
		if unsafe { name.vstring() } == 'NSMutableString' {
			other := api.message(api.cls(c'NSString'), c'stringWithUTF8String:', u64(c'-2.5'), 0, 0)
			api.message(object, c'setString:', other, 0, 0)
			api.check(object, imp, 0xc0200000)
		}
		api.message(object, c'release', 0, 0, 0)
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn string_float_worker(api, cls, imp) }
		for worker in workers { worker.wait() }
	}
	api.drain(pool)
}
fn string_float_constants(api StringFloatApi) {
	text := '-١.٥'
	mut record := [api.cls(c'NSString'), u64(0x7c8), u64(text.str), u64(text.len)]!
	address := u64(unsafe { &record[0] })
	ios_runtime.constants[address] = true
	imp := objc_method_imp(objc_instance_method(record[0], api.sel(c'floatValue')))
	api.check(address, imp, 0xbfc00000)
	wide := [u16(0x2d), 0x661, 0x2e, 0x665, 0]!
	record[1] = 0x7d0; record[2] = u64(unsafe { &wide[0] }); record[3] = 4
	metadata := ObjMetadata{
		image: macho.Image{segments: [macho.Segment{name: '__TEXT', address: 0, filesize: 10, prot: 1}]}
		layout: macho.Layout{size: 10}
		base: record[2]
	}
	metadata.constant_string(address) or { panic(err) }
	unsafe { metadata.image.segments.free() }
	api.check(address, imp, 0xbfc00000)
	cache := ios_runtime.constant_utf8[address] or { panic('missing string cache') }
	ios_runtime.constant_utf8.delete(address); unsafe { cache.free() }
	ios_runtime.constants.delete(address)
}
fn test_string_float_native() {
	$if macos {
		api := StringFloatApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		string_float_shared(api)
		println('IOS-STRING-FLOAT-NATIVE: decimal grammar, BMP digits, whitespace, rounding, metadata, direct IMP, mutation and eight workers PASS')
	}
}
fn test_string_float_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		api := StringFloatApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
		string_float_shared(api)
		string_float_constants(api)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-STRING-FLOAT: decimal grammar, BMP digits, whitespace, rounding, metadata, direct IMP, mutation, constants, eight workers and two balanced lifetimes PASS')
}
