// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.object_getClass(voidptr) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getName(voidptr) &char
fn C.class_copyIvarList(voidptr, &u32) &voidptr
fn C.ivar_getName(voidptr) &char
fn C.ivar_getTypeEncoding(voidptr) &char
fn C.ivar_getOffset(voidptr) isize
fn C.class_copyMethodList(voidptr, &u32) &voidptr
fn C.method_getName(voidptr) voidptr
fn C.sel_getName(voidptr) &char
fn C.method_getTypeEncoding(voidptr) &char
type Send = fn (u64, voidptr, u64) u64
type Init = fn (u64, voidptr, u64, f32, f64) u64
type Get = fn (u64, voidptr) f32
type GetTime = fn (u64, voidptr) f64
type SetTime = fn (u64, voidptr, f64)
type Set = fn (u64, voidptr, f32)
fn msg(object u64, selector &char, argument u64) u64 {
	return unsafe { Send(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), argument) }
}
fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/CoreHaptics.framework/CoreHaptics', 2) != unsafe { nil }
	cls := C.objc_getClass(c'CHHapticDynamicParameter')
	assert cls != unsafe { nil }
	println('CHHapticDynamicParameter SIZE ${C.class_getInstanceSize(cls)} PARENT ${unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() }}')
	mut count := u32(0)
	ivars := C.class_copyIvarList(cls, &count)
	for i in 0 .. int(count) {
		ivar := unsafe { ivars[i] }
		println('IVAR ${unsafe { C.ivar_getName(ivar).vstring() }} ${unsafe { C.ivar_getTypeEncoding(ivar).vstring() }} ${C.ivar_getOffset(ivar)}')
	}
	unsafe { C.free(ivars) }
	for meta in [false, true]! {
		methods := C.class_copyMethodList(if meta { C.object_getClass(cls) } else { cls }, &count)
		for i in 0 .. int(count) {
			method := unsafe { methods[i] }
			println('METHOD ${if meta { "+" } else { "-" }} ${unsafe { C.sel_getName(C.method_getName(method)).vstring() }} ${unsafe { C.method_getTypeEncoding(method).vstring() }}')
		}
		unsafe { C.free(methods) }
	}
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	send := C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')
	id := msg(msg(u64(C.objc_getClass(c'NSMutableString')), c'alloc', 0), c'initWithUTF8String:', u64(c'CustomHapticParameter'))
	assert id != 0
	object := unsafe { Init(send)(msg(u64(cls), c'alloc', 0), C.sel_registerName(c'initWithParameterID:value:relativeTime:'), id, f32(0.25), f64(1.5)) }
	assert object != 0
	stored := msg(object, c'parameterID', 0)
	println('IDENTIFIER same=' + (stored == id).str())
	msg(id, c'appendString:', msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(c'-changed')))
	println('IDENTIFIER after mutation=' + unsafe { (&char(msg(stored, c'UTF8String', 0))).vstring() })
	msg(id, c'release', 0)
	assert msg(object, c'parameterID', 0) == stored
	for raw in [u32(0), 0x80000000, 0xbf800000, 0x40000000, 0x7f800000, 0xff800000, 0x7fc01234]! {
		unsafe { Set(send)(object, C.sel_registerName(c'setValue:'), bits.f32_from_bits(raw)) }
		got := bits.f32_bits(unsafe { Get(send)(object, C.sel_registerName(c'value')) })
		println('VALUE ${raw:08x} -> ${got:08x}')
		assert got == raw
		fresh := unsafe { Init(send)(msg(u64(cls), c'alloc', 0), C.sel_registerName(c'initWithParameterID:value:relativeTime:'), 0, bits.f32_from_bits(raw), f64(1.5)) }
		initialized := bits.f32_bits(unsafe { Get(send)(fresh, C.sel_registerName(c'value')) })
		println('INIT VALUE ${raw:08x} -> ${initialized:08x}')
		assert initialized == raw
		msg(fresh, c'release', 0)
	}
	assert bits.f64_bits(unsafe { GetTime(send)(object, C.sel_registerName(c'relativeTime')) }) == bits.f64_bits(f64(1.5))
	for raw in [u64(0), 0x8000000000000000, 0xbff0000000000000, 0x4000000000000000, 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000001234]! {
		unsafe { SetTime(send)(object, C.sel_registerName(c'setRelativeTime:'), bits.f64_from_bits(raw)) }
		got := bits.f64_bits(unsafe { GetTime(send)(object, C.sel_registerName(c'relativeTime')) })
		println('TIME ${raw:016x} -> ${got:016x}')
		assert got == raw
		fresh := unsafe { Init(send)(msg(u64(cls), c'alloc', 0), C.sel_registerName(c'initWithParameterID:value:relativeTime:'), 0, f32(0.25), bits.f64_from_bits(raw)) }
		initialized := bits.f64_bits(unsafe { GetTime(send)(fresh, C.sel_registerName(c'relativeTime')) })
		println('INIT TIME ${raw:016x} -> ${initialized:016x}')
		assert initialized == raw
		assert bits.f32_bits(unsafe { Get(send)(fresh, C.sel_registerName(c'value')) }) == bits.f32_bits(f32(0.25))
		msg(fresh, c'release', 0)
	}
	println('MIXED float/double constructor preserved independent registers')
	msg(object, c'release', 0)
	nil_id := unsafe { Init(send)(msg(u64(cls), c'alloc', 0), C.sel_registerName(c'initWithParameterID:value:relativeTime:'), 0, f32(-0.5), f64(-2.5)) }
	assert nil_id != 0 && msg(nil_id, c'parameterID', 0) == 0
	println('NIL identifier accepted')
	msg(nil_id, c'release', 0)
	msg(pool, c'drain', 0)
	println('IOS-CH-HAPTIC-DYNAMIC-PARAMETER-INSPECT: identifier lifetime, mutation, nil and exact float/double bits')
}
