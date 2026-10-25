// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.class_addMethod(voidptr, voidptr, voidptr, &char) bool
fn C.class_addIvar(voidptr, &char, usize, u8, &char) bool
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getImplementation(voidptr) voidptr
__global color_init_calls int
type Send = fn (u64, voidptr, u64) u64
type ColorInit = fn (u64, voidptr, f32, f32, f32) u64
type ColorGet = fn (u64, voidptr) f32
fn msg(object u64, selector &char, arg u64) u64 {
	return unsafe { Send(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), arg) }
}
fn subclass_init(object u64, selector voidptr, red f32, green f32, blue f32) u64 {
	color_init_calls++
	imp := C.method_getImplementation(C.class_getInstanceMethod(C.objc_getClass(c'GCColor'), selector))
	return unsafe { ColorInit(imp)(object, selector, red, green, blue) }
}
fn subclass_red(object u64, selector voidptr) f32 { return f32(0.875) }
fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/GameController.framework/GameController', 2) != unsafe { nil }
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	cls := u64(C.objc_getClass(c'GCColor')); assert cls != 0
	send := C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')
	println('SECURE ' + msg(cls, c'supportsSecureCoding', 0).str())
	for values in [[f32(0.25), 0.5, 0.75]!, [f32(-1), 2, 1]!,
		[bits.f32_from_bits(0x7fc01234), bits.f32_from_bits(0x7f800000), bits.f32_from_bits(0xff800000)]!,
		[bits.f32_from_bits(0x80000000), f32(0), f32(1)]!] {
		object := unsafe { ColorInit(send)(msg(cls, c'alloc', 0), C.sel_registerName(c'initWithRed:green:blue:'), values[0], values[1], values[2]) }
		assert object != 0
		for i, selector in [c'red', c'green', c'blue']! {
			value := unsafe { ColorGet(send)(object, C.sel_registerName(selector)) }
			assert bits.f32_bits(value) == bits.f32_bits(values[i])
			println('VALUE ${i} ${bits.f32_bits(values[i]):08x} -> ${bits.f32_bits(value):08x}')
		}
		duplicate := msg(object, c'copyWithZone:', 0)
		assert duplicate != 0 && duplicate != object
		println('COPY same=' + (duplicate == object).str())
		println('DESCRIPTION ' + unsafe { (&char(msg(msg(object, c'description', 0), c'UTF8String', 0))).vstring() })
		msg(object, c'release', 0)
		for i, selector in [c'red', c'green', c'blue']! {
			assert bits.f32_bits(unsafe { ColorGet(send)(duplicate, C.sel_registerName(selector)) }) == bits.f32_bits(values[i])
		}
		msg(duplicate, c'release', 0)
	}
	object := msg(cls, c'new', 0)
	for selector in [c'red', c'green', c'blue']! {
		value := bits.f32_bits(unsafe { ColorGet(send)(object, C.sel_registerName(selector)) })
		assert value == 0
		println('DEFAULT ' + value.str())
	}
	msg(object, c'release', 0)
	sub := C.objc_allocateClassPair(unsafe { voidptr(cls) }, c'VinixNativeColor', 0)
	assert sub != unsafe { nil }
	assert C.class_addIvar(sub, c'_extra', 8, 3, c'Q')
	C.objc_registerClassPair(sub)
	child := unsafe { ColorInit(send)(msg(u64(sub), c'alloc', 0), C.sel_registerName(c'initWithRed:green:blue:'), f32(0.25), f32(0.5), f32(0.75)) }
	unsafe { *(&u64(child + 24)) = 0x123456789abcdef0 }
	assert C.class_addMethod(sub, C.sel_registerName(c'initWithRed:green:blue:'), unsafe { voidptr(subclass_init) }, c'@28@0:8f16f20f24')
	assert C.class_addMethod(sub, C.sel_registerName(c'red'), unsafe { voidptr(subclass_red) }, c'f16@0:8')
	duplicate := msg(child, c'copy', 0)
	println('SUBCLASS COPY preserved=' + (msg(duplicate, c'class', 0) == u64(sub)).str())
	assert msg(duplicate, c'class', 0) == u64(sub)
	getter := C.method_getImplementation(C.class_getInstanceMethod(unsafe { voidptr(cls) }, C.sel_registerName(c'red')))
	println('SUBCLASS COPY init-calls=${color_init_calls} stored-red=${bits.f32_bits(unsafe { ColorGet(getter)(duplicate, C.sel_registerName(c'red')) }):08x}')
	println('SUBCLASS COPY extra=${unsafe { *(&u64(duplicate + 24)) }:016x}')
	assert color_init_calls == 0
	assert bits.f32_bits(unsafe { ColorGet(getter)(duplicate, C.sel_registerName(c'red')) }) == 0x3e800000
	assert unsafe { *(&u64(duplicate + 24)) } == 0
	msg(duplicate, c'release', 0); msg(child, c'release', 0)
	msg(pool, c'drain', 0)
	println('IOS-GC-COLOR-INSPECT: exact float bits, independent copy, zero default and preserved subclass')
}
