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
type InitPattern = fn (u64, voidptr, u64, u64, &u64) u64
type InitEvent = fn (u64, voidptr, u64, u64, f64, f64) u64
type Get = fn (u64, voidptr) f64
type GetFloat = fn (u64, voidptr) f32
type Set = fn (u64, voidptr, f64)
fn msg(object u64, selector &char, argument u64) u64 {
	return unsafe { Send(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), argument) }
}
fn duration(object u64) f64 {
	return unsafe { Get(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(c'duration')) }
}
fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/CoreHaptics.framework/CoreHaptics', 2) != unsafe { nil }
	cls := C.objc_getClass(c'CHHapticPattern')
	assert cls != unsafe { nil }
	assert C.class_getInstanceSize(cls) == 72 && C.class_getSuperclass(cls) == C.objc_getClass(c'NSObject')
	println('CHHapticPattern SIZE ${C.class_getInstanceSize(cls)} PARENT ${unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() }}')
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
	kind := msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(c'HapticContinuous'))
	event := unsafe { InitEvent(send)(msg(u64(C.objc_getClass(c'CHHapticEvent')), c'alloc', 0), C.sel_registerName(c'initWithEventType:parameters:relativeTime:duration:'), kind, 0, 1.25, 3.5) }
	events := msg(u64(C.objc_getClass(c'NSMutableArray')), c'new', 0)
	msg(events, c'addObject:', event)
	for selector in [c'initWithEvents:parameters:error:', c'initWithEvents:parameterCurves:error:']! {
		for nil_events in [false, true]! {
			mut err := u64(0x1234)
			object := unsafe { InitPattern(send)(msg(u64(cls), c'alloc', 0), C.sel_registerName(selector), if nil_events { 0 } else { events }, 0, &err) }
			println('INIT ${unsafe { selector.vstring() }} nil=${nil_events} OK ${object != 0} ERROR ${err.hex()} DURATION ${duration(object)}')
			assert object != 0
			assert err == 0x1234 && duration(object) == if nil_events { 0.0 } else { 4.75 }
			stored_events := msg(object, c'events', 0)
			for offset in [8, 16, 24, 32, 40, 48, 56, 64]! {
				value := unsafe { *(&u64(object + u64(offset))) }
				println('SLOT ${offset} NIL ${value == 0} CLASS ${if value == 0 { '(nil)' } else { unsafe { C.class_getName(C.object_getClass(voidptr(value))).vstring() } }}')
			}
			assert stored_events != 0 && stored_events != events
			assert msg(stored_events, c'count', 0) == if nil_events { u64(0) } else { 1 }
			assert msg(object, c'parameters', 0) != 0 && msg(object, c'parameterCurves', 0) != 0
			assert msg(msg(object, c'parameters', 0), c'count', 0) == 0 && msg(msg(object, c'parameterCurves', 0), c'count', 0) == 0
			assert msg(object, c'patternID', 0) == 0 && msg(object, c'configurationDictionary', 0) == 0
			assert unsafe { GetFloat(send)(object, C.sel_registerName(c'version')) } == 0
			for property in [c'events', c'parameters', c'parameterCurves', c'patternID', c'configurationDictionary']! {
				value := msg(object, property, 0)
				println('GET ${unsafe { property.vstring() }} NIL ${value == 0} CLASS ${if value == 0 { '(nil)' } else { unsafe { C.class_getName(C.object_getClass(voidptr(value))).vstring() } }} COUNT ${if property in [c'events', c'parameters', c'parameterCurves']! { msg(value, c'count', 0) } else { 0 }} SAME ${value == events}')
			}
			println('VERSION ${unsafe { GetFloat(send)(object, C.sel_registerName(c'version')) }}')
			if !nil_events {
				assert msg(stored_events, c'objectAtIndex:', 0) == event
				msg(events, c'removeAllObjects', 0)
				assert duration(object) == 4.75 && msg(stored_events, c'count', 0) == 1
				msg(events, c'addObject:', event)
				unsafe { Set(send)(event, C.sel_registerName(c'setRelativeTime:'), 8.0) }
				assert duration(object) == 11.5
				println('AFTER EVENT MUTATION ${duration(object)}')
				unsafe { Set(send)(event, C.sel_registerName(c'setRelativeTime:'), 1.25) }
			}
			msg(object, c'release', 0)
		}
	}
	unsafe { Set(send)(event, C.sel_registerName(c'setRelativeTime:'), 1.25); Set(send)(event, C.sel_registerName(c'setDuration:'), 3.5) }
	second := unsafe { InitEvent(send)(msg(u64(C.objc_getClass(c'CHHapticEvent')), c'alloc', 0), C.sel_registerName(c'initWithEventType:parameters:relativeTime:duration:'), kind, 0, 2.0, 0.5) }
	msg(events, c'addObject:', second)
	mut error_slot := u64(0x1234)
	pattern := unsafe { InitPattern(send)(msg(u64(cls), c'alloc', 0), C.sel_registerName(c'initWithEvents:parameters:error:'), events, 0, &error_slot) }
	assert duration(pattern) == 4.75
	println('OVERLAPPING EVENTS DURATION ${duration(pattern)}')
	assert unsafe { InitPattern(send)(pattern, C.sel_registerName(c'initWithEvents:parameterCurves:error:'), events, 0, &error_slot) } == pattern
	println('REINIT PARAMS NIL ${unsafe { *(&u64(pattern + 56)) } == 0} CURVES NIL ${unsafe { *(&u64(pattern + 64)) } == 0}')
	assert unsafe { *(&u64(pattern + 56)) } != 0 && unsafe { *(&u64(pattern + 64)) } != 0
	assert duration(pattern) == 4.75
	msg(events, c'removeAllObjects', 0)
	msg(events, c'addObject:', event)
	assert duration(pattern) == 4.75
	msg(pattern, c'release', 0); msg(second, c'release', 0)
	for raw in [u64(0), 0x8000000000000000, 0xbff0000000000000, 0x4000000000000000, 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000001234]! {
		unsafe { Set(send)(event, C.sel_registerName(c'setRelativeTime:'), bits.f64_from_bits(raw)); Set(send)(event, C.sel_registerName(c'setDuration:'), 0.0) }
		mut err := u64(0)
		object := unsafe { InitPattern(send)(msg(u64(cls), c'alloc', 0), C.sel_registerName(c'initWithEvents:parameters:error:'), events, 0, &err) }
		println('TIME ${raw.hex()} OK ${object != 0} ERROR ${err.hex()} DURATION ${bits.f64_bits(duration(object)).hex()}')
		expected := if bits.f64_from_bits(raw) > 0 { raw } else { u64(0) }
		assert object != 0 && err == 0 && bits.f64_bits(duration(object)) == expected
		msg(object, c'release', 0)
	}
	for time in [-2.0, 2.0, 0.0]! {
		for length in [-4.0, 4.0, 0.0]! {
			unsafe { Set(send)(event, C.sel_registerName(c'setRelativeTime:'), time); Set(send)(event, C.sel_registerName(c'setDuration:'), length) }
			object := unsafe { InitPattern(send)(msg(u64(cls), c'alloc', 0), C.sel_registerName(c'initWithEvents:parameters:error:'), events, 0, &error_slot) }
			println('END TIME ${time} LENGTH ${length} DURATION ${duration(object)}')
			assert duration(object) == if time + length > 0 { time + length } else { 0.0 }
			msg(object, c'release', 0)
		}
	}
	msg(event, c'release', 0); msg(events, c'release', 0); msg(pool, c'drain', 0)
	println('NATIVE-HAPTICPATTERN: PASS')
}
