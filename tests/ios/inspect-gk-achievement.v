// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getName(voidptr) &char
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char

type AchievementSend = fn (u64, voidptr, u64, u64) u64
type AchievementGetDouble = fn (u64, voidptr) f64
type AchievementSetDouble = fn (u64, voidptr, f64)
fn msg(object u64, selector &char, a u64) u64 {
	return unsafe { AchievementSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), a, 0) }
}
fn text(object u64) string {
	if object == 0 { return '<nil>' }
	return unsafe { (&char(msg(object, c'UTF8String', 0))).vstring() }
}
fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/GameKit.framework/GameKit', 2) != unsafe { nil }
	cls := C.objc_getClass(c'GKAchievement')
	assert cls != unsafe { nil }
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	println('GKAchievement SIZE ${C.class_getInstanceSize(cls)} PARENT ${unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() }}')
	for selector in [c'init', c'initWithIdentifier:', c'identifier', c'setIdentifier:', c'percentComplete', c'setPercentComplete:', c'isCompleted', c'isHidden', c'lastReportedDate', c'showsCompletionBanner', c'setShowsCompletionBanner:', c'player', c'playerID', c'copyWithZone:']! {
		method := C.class_getInstanceMethod(cls, C.sel_registerName(selector))
		if method != unsafe { nil } { println('INSTANCE ${unsafe { selector.vstring() }} ${unsafe { C.method_getTypeEncoding(method).vstring() }}') }
		else { println('ABSENT ${unsafe { selector.vstring() }}') }
	}
	get_double := unsafe { AchievementGetDouble(C.dlsym(voidptr(i64(-2)), c'objc_msgSend')) }
	set_double := unsafe { AchievementSetDouble(C.dlsym(voidptr(i64(-2)), c'objc_msgSend')) }
	for init_selector in [c'init', c'initWithIdentifier:']! {
		identifier := msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(c'vinix.achievement'))
		object := msg(msg(u64(cls), c'alloc', 0), init_selector, identifier)
		assert object != 0
		println('IDENTIFIER ${unsafe { init_selector.vstring() }} ${text(msg(object, c'identifier', 0))}')
		assert text(msg(object, c'identifier', 0)) == if init_selector == c'init' { '*uninitialized achievement identifier*' } else { 'vinix.achievement' }
		for selector in [c'identifier', c'setIdentifier:', c'percentComplete', c'setPercentComplete:', c'isCompleted', c'isHidden', c'lastReportedDate', c'showsCompletionBanner', c'setShowsCompletionBanner:']! {
			signature := msg(object, c'methodSignatureForSelector:', u64(C.sel_registerName(selector)))
			mut types := unsafe { (&char(msg(signature, c'methodReturnType', 0))).vstring().clone() }
			for i in 0 .. msg(signature, c'numberOfArguments', 0) { types += unsafe { (&char(msg(signature, c'getArgumentTypeAtIndex:', i))).vstring() } }
			println('SIGNATURE ${unsafe { selector.vstring() }} ${types}')
		}
		println('DEFAULT ${unsafe { init_selector.vstring() }} identifier=${msg(object, c'identifier', 0)} percent=${get_double(object, C.sel_registerName(c'percentComplete'))} completed=${msg(object, c'isCompleted', 0)} banner=${msg(object, c'showsCompletionBanner', 0)} date=${msg(object, c'lastReportedDate', 0)} player=${msg(object, c'player', 0)} hidden=${msg(object, c'isHidden', 0)}')
		for value in [f64(-10), 0, 50.5, 99.999, 100, 101, 1000, math.nan(), math.inf(1), math.inf(-1)]! {
			set_double(object, C.sel_registerName(c'setPercentComplete:'), value)
			assert if math.is_nan(value) { math.is_nan(get_double(object, C.sel_registerName(c'percentComplete'))) } else { get_double(object, C.sel_registerName(c'percentComplete')) == value }
			assert msg(object, c'isCompleted', 0) == u64(value >= 100)
			println('PERCENT ${value} -> ${get_double(object, C.sel_registerName(c'percentComplete'))} completed=${msg(object, c'isCompleted', 0)}')
		}
		for value in [u64(0), 1, 7, 255, 256]! {
			msg(object, c'setShowsCompletionBanner:', value)
			assert msg(object, c'showsCompletionBanner', 0) == u64(u8(value) != 0)
			println('BANNER ${value} -> ${msg(object, c'showsCompletionBanner', 0)}')
		}
		mutable := msg(u64(C.objc_getClass(c'NSMutableString')), c'stringWithUTF8String:', u64(c'before'))
		msg(object, c'setIdentifier:', mutable)
		msg(mutable, c'appendString:', msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(c'.after')))
		assert msg(object, c'identifier', 0) == mutable
		assert text(msg(object, c'identifier', 0)) == 'before.after'
		date := msg(object, c'lastReportedDate', 0)
		assert date != 0
		set_double(object, C.sel_registerName(c'setPercentComplete:'), 100)
		assert msg(object, c'lastReportedDate', 0) == date
		println('OWNERSHIP identifier is retained; progress leaves creation date unchanged')
		msg(object, c'initWithIdentifier:', 0)
		assert msg(object, c'identifier', 0) == 0
		assert get_double(object, C.sel_registerName(c'percentComplete')) == 0
		assert msg(object, c'isCompleted', 0) == 0 && msg(object, c'showsCompletionBanner', 0) == 1
		assert msg(object, c'lastReportedDate', 0) != 0
		println('REINIT identifier=${msg(object, c'identifier', 0)} percent=${get_double(object, C.sel_registerName(c'percentComplete'))} completed=${msg(object, c'isCompleted', 0)} banner=${msg(object, c'showsCompletionBanner', 0)}')
		assert msg(object, c'initWithIdentifier:', mutable) == object
		assert msg(object, c'identifier', 0) == mutable
		msg(mutable, c'appendString:', identifier)
		assert text(msg(object, c'identifier', 0)) == 'before.aftervinix.achievement'
		msg(object, c'release', 0)
	}
	msg(pool, c'drain', 0)
	println('IOS-GKACHIEVEMENT-INSPECT: PASS')
}
