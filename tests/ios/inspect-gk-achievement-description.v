// SPDX-License-Identifier: GPL-2.0-or-later
module main

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

type DescriptionSend = fn (u64, voidptr, u64, u64) u64
fn msg(object u64, selector &char, a u64) u64 {
	return unsafe { DescriptionSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), a, 0) }
}
fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/GameKit.framework/GameKit', 2) != unsafe { nil }
	cls := C.objc_getClass(c'GKAchievementDescription')
	assert cls != unsafe { nil }
	assert C.class_getInstanceSize(cls) == 24
	assert unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() } == 'NSObject'
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	println('GKAchievementDescription SIZE ${C.class_getInstanceSize(cls)} PARENT ${unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() }}')
	for initialization in [c'init', c'new']! {
		object := if initialization == c'new' { msg(u64(cls), initialization, 0) } else { msg(msg(u64(cls), c'alloc', 0), initialization, 0) }
		assert object != 0
		for selector in [c'identifier', c'groupIdentifier', c'title', c'achievedDescription', c'unachievedDescription', c'maximumPoints', c'isHidden', c'isReplayable', c'image', c'rarityPercent', c'releaseState', c'activityIdentifier', c'activityProperties']! {
			method := C.class_getInstanceMethod(cls, C.sel_registerName(selector))
			assert (method != unsafe { nil }) == (selector == c'image')
			if selector == c'image' { assert unsafe { C.method_getTypeEncoding(method).vstring() } == '@16@0:8' }
			if method != unsafe { nil } { println('INSTANCE ${unsafe { selector.vstring() }} ${unsafe { C.method_getTypeEncoding(method).vstring() }}') }
			else { println('ABSENT ${unsafe { selector.vstring() }}') }
			signature := msg(object, c'methodSignatureForSelector:', u64(C.sel_registerName(selector)))
			assert signature != 0
			mut types := unsafe { (&char(msg(signature, c'methodReturnType', 0))).vstring().clone() }
			for i in 0 .. msg(signature, c'numberOfArguments', 0) { types += unsafe { (&char(msg(signature, c'getArgumentTypeAtIndex:', i))).vstring() } }
			value := msg(object, selector, 0)
			expected := match unsafe { selector.vstring() } {
				'maximumPoints' { 'S@:' }
				'isHidden', 'isReplayable' { 'B@:' }
				'releaseState' { 'Q@:' }
				else { '@@:' }
			}
			assert types == expected && value == 0
			println('DEFAULT ${unsafe { initialization.vstring() }} ${unsafe { selector.vstring() }} ${types} ${value}')
		}
		assert msg(object, c'init', 0) == object
		msg(object, c'release', 0)
	}
	msg(pool, c'drain', 0)
	println('IOS-GKACHIEVEMENTDESCRIPTION-INSPECT: PASS')
}
