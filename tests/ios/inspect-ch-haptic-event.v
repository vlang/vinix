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
type Init = fn (u64, voidptr, u64, u64, f64) u64
type InitDuration = fn (u64, voidptr, u64, u64, f64, f64) u64
type Get = fn (u64, voidptr) f64
type Set = fn (u64, voidptr, f64)
fn msg(object u64, selector &char, argument u64) u64 {
	return unsafe { Send(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), argument) }
}
fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/CoreHaptics.framework/CoreHaptics', 2) != unsafe { nil }
	cls := C.objc_getClass(c'CHHapticEvent')
	assert cls != unsafe { nil }
	assert C.class_getInstanceSize(cls) == 48
	assert C.class_getSuperclass(cls) == C.objc_getClass(c'NSObject')
	println('CHHapticEvent SIZE ${C.class_getInstanceSize(cls)} PARENT ${unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() }}')
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
	send := C.dlsym(voidptr(i64(-2)), c'objc_msgSend')
	type_id := msg(msg(u64(C.objc_getClass(c'NSMutableString')), c'alloc', 0), c'initWithUTF8String:', u64(c'CustomEvent'))
	parameter := msg(u64(C.objc_getClass(c'NSObject')), c'new', 0)
	params := msg(u64(C.objc_getClass(c'NSMutableArray')), c'new', 0)
	msg(params, c'addObject:', parameter)
	event := unsafe { InitDuration(send)(msg(u64(cls), c'alloc', 0), C.sel_registerName(c'initWithEventType:parameters:relativeTime:duration:'), type_id, params, -2.5, -3.5) }
	assert event != 0
	stored := msg(event, c'eventParameters', 0)
	assert msg(event, c'type', 0) == type_id && stored != params
	assert msg(stored, c'objectAtIndex:', 0) == parameter
	println('TYPE IDENTITY ${msg(event, c'type', 0) == type_id} ARRAY IDENTITY ${stored == params} ELEMENT IDENTITY ${msg(stored, c'objectAtIndex:', 0) == parameter}')
	msg(type_id, c'appendString:', msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(c'-changed')))
	msg(params, c'removeAllObjects', 0)
	msg(type_id, c'release', 0); msg(params, c'release', 0); msg(parameter, c'release', 0)
	assert unsafe { cstring_to_vstring(&char(msg(msg(event, c'type', 0), c'UTF8String', 0))) } == 'CustomEvent-changed'
	assert msg(stored, c'count', 0) == 1
	assert unsafe { Get(send)(event, C.sel_registerName(c'relativeTime')) } == -2.5
	assert unsafe { Get(send)(event, C.sel_registerName(c'duration')) } == -3.5
	assert msg(event, c'audioResID', 0) == ~u64(0)
	println('TYPE AFTER MUTATION ${unsafe { cstring_to_vstring(&char(msg(msg(event, c'type', 0), c'UTF8String', 0))) }} ARRAY COUNT ${msg(stored, c'count', 0)}')
	println('INITIAL TIME ${unsafe { Get(send)(event, C.sel_registerName(c'relativeTime')) }} DURATION ${unsafe { Get(send)(event, C.sel_registerName(c'duration')) }} AUDIO ${msg(event, c'audioResID', 0)}')
	assert unsafe { InitDuration(send)(event, C.sel_registerName(c'initWithEventType:parameters:relativeTime:duration:'), type_id, stored, 0, 0) } == event
	assert msg(event, c'type', 0) == type_id && msg(event, c'eventParameters', 0) == stored
	println('REINIT borrowed type and immutable parameter snapshot preserve identity')
	for raw in [u64(0), 0x8000000000000000, 0xbff0000000000000, 0x4000000000000000, 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000001234]! {
		for property in ['relativeTime', 'duration']! {
			selector := if property == 'relativeTime' { c'setRelativeTime:' } else { c'setDuration:' }
			unsafe { Set(send)(event, C.sel_registerName(selector), bits.f64_from_bits(raw)) }
			actual := bits.f64_bits(unsafe { Get(send)(event, C.sel_registerName(property.str)) })
			assert actual == raw
			println('SET ${property} ${raw.hex()} ${actual.hex()}')
		}
		fresh := unsafe { InitDuration(send)(msg(u64(cls), c'alloc', 0), C.sel_registerName(c'initWithEventType:parameters:relativeTime:duration:'), 0, 0, bits.f64_from_bits(raw), bits.f64_from_bits(raw)) }
		assert fresh != 0 && msg(fresh, c'type', 0) == 0 && msg(fresh, c'eventParameters', 0) == 0
		assert bits.f64_bits(unsafe { Get(send)(fresh, C.sel_registerName(c'relativeTime')) }) == raw
		assert bits.f64_bits(unsafe { Get(send)(fresh, C.sel_registerName(c'duration')) }) == raw
		println('INIT ${raw.hex()} ${raw.hex()}')
		msg(fresh, c'release', 0)
	}
	for audio in [false, true]! {
		for duration in [false, true]! {
			selector := if audio { if duration { c'initWithAudioResourceID:parameters:relativeTime:duration:' } else { c'initWithAudioResourceID:parameters:relativeTime:' } } else { if duration { c'initWithEventType:parameters:relativeTime:duration:' } else { c'initWithEventType:parameters:relativeTime:' } }
			fresh := if duration { unsafe { InitDuration(send)(msg(u64(cls), c'alloc', 0), C.sel_registerName(selector), if audio { u64(0xfedcba9876543210) } else { 0 }, 0, -1.25, 4.5) } } else { unsafe { Init(send)(msg(u64(cls), c'alloc', 0), C.sel_registerName(selector), if audio { u64(0xfedcba9876543210) } else { 0 }, 0, -1.25) } }
			assert fresh != 0
			assert msg(fresh, c'eventParameters', 0) == 0
			assert msg(fresh, c'audioResID', 0) == if audio { u64(0xfedcba9876543210) } else { ~u64(0) }
			assert unsafe { Get(send)(fresh, C.sel_registerName(c'relativeTime')) } == -1.25
			assert unsafe { Get(send)(fresh, C.sel_registerName(c'duration')) } == if duration { 4.5 } else { 0.0 }
			assert if audio { unsafe { cstring_to_vstring(&char(msg(msg(fresh, c'type', 0), c'UTF8String', 0))) } == 'AudioCustom' } else { msg(fresh, c'type', 0) == 0 }
			println('CONSTRUCTOR audio=${audio} duration=${duration} TYPE ${if msg(fresh, c'type', 0) == 0 { '(nil)' } else { unsafe { cstring_to_vstring(&char(msg(msg(fresh, c'type', 0), c'UTF8String', 0))) } }} AUDIO ${msg(fresh, c'audioResID', 0).hex()} TIME ${unsafe { Get(send)(fresh, C.sel_registerName(c'relativeTime')) }} DURATION ${unsafe { Get(send)(fresh, C.sel_registerName(c'duration')) }}')
			msg(fresh, c'release', 0)
		}
	}
	msg(event, c'release', 0); msg(pool, c'drain', 0)
	println('NATIVE-HAPTICEVENT: PASS')
}
