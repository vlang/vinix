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
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char

type LocalSend = fn (u64, voidptr, u64, u64) u64
fn msg(object u64, selector &char, a u64) u64 {
	return unsafe { LocalSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), a, 0) }
}
fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/GameKit.framework/GameKit', 2) != unsafe { nil }
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	cls := C.objc_getClass(c'GKLocalPlayer')
	assert C.class_getInstanceSize(cls) == 120
	assert C.class_getSuperclass(cls) == C.objc_getClass(c'GKPlayer')
	println('GKLocalPlayer SIZE 120 PARENT GKPlayer')
	cached := msg(u64(cls), c'localPlayer', 0)
	assert cached != 0 && cached == msg(u64(cls), c'local', 0)
	for constructor in [c'new', c'init', c'localPlayer', c'local']! {
		object := if constructor == c'init' { msg(msg(u64(cls), c'alloc', 0), constructor, 0) } else { msg(u64(cls), constructor, 0) }
		assert object != 0
		owned := constructor in [c'new', c'init']!
		assert (object != cached) == owned
		if owned { assert msg(object, c'retainCount', 0) == 1 }
		println('CONSTRUCT ${unsafe { constructor.vstring() }} singleton ${!owned}')
		for selector in [c'playerID', c'displayName', c'alias', c'guestIdentifier', c'isFriend', c'isInvitable', c'scopedIDsArePersistent', c'isAuthenticated', c'isUnderage', c'isMultiplayerGamingRestricted', c'isPersonalizedCommunicationRestricted', c'authenticateHandler']! {
			value := msg(object, selector, 0)
			boolean := selector in [c'isFriend', c'isInvitable', c'scopedIDsArePersistent', c'isAuthenticated', c'isUnderage', c'isMultiplayerGamingRestricted', c'isPersonalizedCommunicationRestricted']!
			block := selector == c'authenticateHandler'
			if selector == c'alias' { assert value != 0 }
			else { assert value == if selector in [c'isMultiplayerGamingRestricted', c'isPersonalizedCommunicationRestricted']! { u64(1) } else { u64(0) } }
			text := if selector in [c'playerID', c'displayName', c'alias', c'guestIdentifier']! && value != 0 { unsafe { (&char(msg(value, c'UTF8String', 0))).vstring().clone() } } else { value.str() }
			if selector == c'alias' { assert text == 'Unknown' }
			signature := msg(object, c'methodSignatureForSelector:', u64(C.sel_registerName(selector)))
			assert signature != 0 && msg(signature, c'numberOfArguments', 0) == 2
			assert msg(signature, c'methodReturnLength', 0) == if boolean { u64(1) } else { u64(8) }
			mut types := unsafe { (&char(msg(signature, c'methodReturnType', 0))).vstring().clone() }
			for i in 0 .. msg(signature, c'numberOfArguments', 0) { types += unsafe { (&char(msg(signature, c'getArgumentTypeAtIndex:', i))).vstring() } }
			assert types == if boolean { 'B@:' } else if block { '@?@:' } else { '@@:' }
			println('DEFAULT ${unsafe { constructor.vstring() }} ${unsafe { selector.vstring() }} ${types} ${text}')
			method := C.class_getInstanceMethod(cls, C.sel_registerName(selector))
			forwarded := selector in [c'guestIdentifier', c'isFriend', c'isUnderage']!
			assert (method == unsafe { nil }) == forwarded
			if !forwarded { assert unsafe { C.method_getTypeEncoding(method).vstring() } == if boolean { 'B16@0:8' } else if block { '@?16@0:8' } else { '@16@0:8' } }
			println('DIRECT ${unsafe { selector.vstring() }} ' + if method == unsafe { nil } { 'forwarded' } else { unsafe { C.method_getTypeEncoding(method).vstring() } })
		}
		for selector in [c'copy', c'copyWithZone:']! {
			copied := msg(object, selector, 0)
			assert copied == object
			if owned { assert msg(object, c'retainCount', 0) == 2 }
			println('COPY ${unsafe { constructor.vstring() }} ${unsafe { selector.vstring() }} retained self')
			msg(copied, c'release', 0)
		}
		if constructor in [c'new', c'init']! { msg(object, c'release', 0) }
	}
	for selector in [c'localPlayer', c'local']! {
		method := C.class_getClassMethod(cls, C.sel_registerName(selector))
		assert method != unsafe { nil } && unsafe { C.method_getTypeEncoding(method).vstring() } == '@16@0:8'
		println('CLASS ${unsafe { selector.vstring() }} ${unsafe { C.method_getTypeEncoding(method).vstring() }}')
	}
	msg(pool, c'drain', 0)
	println('IOS-GKLOCALPLAYER-INSPECT: PASS')
}
