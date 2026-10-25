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

type MatchSend = fn (u64, voidptr, u64, u64) u64
fn msg(object u64, selector &char, a u64) u64 {
	return unsafe { MatchSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), a, 0) }
}
fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/GameKit.framework/GameKit', 2) != unsafe { nil }
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	cls := C.objc_getClass(c'GKTurnBasedMatch')
	assert cls != unsafe { nil } && C.class_getInstanceSize(cls) == 40
	assert unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() } == 'NSObject'
	println('GKTurnBasedMatch SIZE 40 PARENT NSObject')
	for initialization in [c'init', c'new']! {
		object := if initialization == c'new' { msg(u64(cls), initialization, 0) } else { msg(msg(u64(cls), c'alloc', 0), initialization, 0) }
		assert object != 0 && msg(object, c'class', 0) == u64(cls)
		for selector in [c'init', c'matchID', c'creationDate', c'participants', c'status', c'currentParticipant', c'matchData', c'message', c'setMessage:', c'matchDataMaximumSize', c'exchanges', c'activeExchanges', c'completedExchanges', c'exchangeDataMaximumSize', c'exchangeMaxInitiatedExchangesPerPlayer']! {
			assert msg(object, c'respondsToSelector:', u64(C.sel_registerName(selector))) != 0
			class_response := selector == c'init'
			assert (msg(u64(cls), c'respondsToSelector:', u64(C.sel_registerName(selector))) != 0) == class_response
			println('CLASS ${unsafe { selector.vstring() }} responds=${class_response}')
			method := C.class_getInstanceMethod(cls, C.sel_registerName(selector))
			forwarded := selector in [c'matchID', c'creationDate', c'matchData']!
			assert (method == unsafe { nil }) == forwarded
			expected := match unsafe { selector.vstring() } {
				'status' { 'q16@0:8' }
				'matchDataMaximumSize', 'exchangeDataMaximumSize', 'exchangeMaxInitiatedExchangesPerPlayer' { 'Q16@0:8' }
				'setMessage:' { 'v24@0:8@16' }
				else { '@16@0:8' }
			}
			if !forwarded { assert unsafe { C.method_getTypeEncoding(method).vstring() } == expected }
			signature := msg(object, c'methodSignatureForSelector:', u64(C.sel_registerName(selector)))
			assert signature != 0
			argc := if selector == c'setMessage:' { u64(3) } else { u64(2) }
			assert msg(signature, c'numberOfArguments', 0) == argc
			mut types := unsafe { (&char(msg(signature, c'methodReturnType', 0))).vstring().clone() }
			for i in 0 .. argc { types += '|' + unsafe { (&char(msg(signature, c'getArgumentTypeAtIndex:', i))).vstring() } }
			assert types == expected[..1] + '|@|:' + if argc == 3 { '|@' } else { '' }
			println('SIGNATURE ${unsafe { initialization.vstring() }} ${unsafe { selector.vstring() }} ${types} forwarded=${forwarded}')
			if selector !in [c'init', c'setMessage:']! {
				value := match unsafe { selector.vstring() } {
					'matchDataMaximumSize' { u64(65536) }
					'exchangeDataMaximumSize' { u64(1024) }
					'exchangeMaxInitiatedExchangesPerPlayer' { u64(30) }
					else { u64(0) }
				}
				assert msg(object, selector, 0) == value
				println('DEFAULT ${unsafe { initialization.vstring() }} ${unsafe { selector.vstring() }} ${value}')
			}
		}
		text := msg(u64(C.objc_getClass(c'NSMutableString')), c'new', 0)
		msg(text, c'appendString:', msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(c'hello')))
		msg(object, c'setMessage:', text)
		assert msg(object, c'message', 0) == text
		msg(text, c'appendString:', msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(c' mutated')))
		assert unsafe { (&char(msg(msg(object, c'message', 0), c'UTF8String', 0))).vstring() } == 'hello mutated'
		msg(text, c'release', 0)
		assert msg(object, c'message', 0) == text
		println('MESSAGE ${unsafe { initialization.vstring() }} retained mutable identity hello mutated')
		for selector in [c'copy', c'copyWithZone:']! {
			copied := msg(object, selector, 0)
			copy_cls := voidptr(msg(copied, c'class', 0))
			assert copied != 0 && copied != object && copy_cls != cls
			assert unsafe { C.class_getName(copy_cls).vstring() } == 'GKTurnBasedMatchInternal'
			assert C.class_getInstanceSize(copy_cls) == 176
			assert unsafe { C.class_getName(C.class_getSuperclass(copy_cls)).vstring() } == 'GKInternalRepresentation'
			assert msg(copied, c'message', 0) == text
			msg(copied, c'release', 0)
			println('COPY ${unsafe { initialization.vstring() }} ${unsafe { selector.vstring() }} distinct GKTurnBasedMatchInternal SIZE 176 PARENT GKInternalRepresentation shared message; unsupported boundary')
		}
		msg(object, c'setMessage:', 0); assert msg(object, c'message', 0) == 0
		println('NIL ${unsafe { initialization.vstring() }} clears message')
		msg(object, c'setMessage:', msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(c'reset')))
		assert msg(object, c'init', 0) == object && msg(object, c'message', 0) == 0
		println('REINIT ${unsafe { initialization.vstring() }} resets message')
		msg(object, c'release', 0)
	}
	msg(pool, c'drain', 0)
	println('IOS-GKTURNBASEDMATCH-INSPECT: PASS')
}
