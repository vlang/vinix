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

type ParticipantSend = fn (u64, voidptr, u64, u64) u64
fn msg(object u64, selector &char, a u64) u64 {
	return unsafe { ParticipantSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), a, 0) }
}
fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/GameKit.framework/GameKit', 2) != unsafe { nil }
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	cls := C.objc_getClass(c'GKTurnBasedParticipant')
	assert cls != unsafe { nil } && C.class_getInstanceSize(cls) == 16
	assert unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() } == 'NSObject'
	println('GKTurnBasedParticipant SIZE 16 PARENT NSObject')
	for initialization in [c'init', c'new']! {
		object := if initialization == c'new' { msg(u64(cls), initialization, 0) } else { msg(msg(u64(cls), c'alloc', 0), initialization, 0) }
		assert object != 0
		for selector in [c'player', c'playerID', c'lastTurnDate', c'timeoutDate', c'status', c'matchOutcome', c'setMatchOutcome:', c'copy', c'copyWithZone:', c'init']! {
			assert msg(object, c'respondsToSelector:', u64(C.sel_registerName(selector))) != 0
			class_response := selector in [c'init', c'copy', c'copyWithZone:']!
			assert (msg(u64(cls), c'respondsToSelector:', u64(C.sel_registerName(selector))) != 0) == class_response
			if selector in [c'copy', c'copyWithZone:']! { assert msg(u64(cls), selector, 0) == u64(cls) }
			println('CLASS ${unsafe { selector.vstring() }} responds=${class_response}')
			method := C.class_getInstanceMethod(cls, C.sel_registerName(selector))
			forwarded := selector in [c'timeoutDate', c'matchOutcome', c'setMatchOutcome:', c'copyWithZone:']!
			assert (method == unsafe { nil }) == forwarded
			if !forwarded { assert unsafe { C.method_getTypeEncoding(method).vstring() } == if selector == c'status' { 'q16@0:8' } else { '@16@0:8' } }
			signature := msg(object, c'methodSignatureForSelector:', u64(C.sel_registerName(selector)))
			assert signature != 0
			argc := if selector in [c'setMatchOutcome:', c'copyWithZone:']! { u64(3) } else { u64(2) }
			assert msg(signature, c'numberOfArguments', 0) == argc
			mut types := unsafe { (&char(msg(signature, c'methodReturnType', 0))).vstring().clone() }
			for i in 0 .. argc { types += '|' + unsafe { (&char(msg(signature, c'getArgumentTypeAtIndex:', i))).vstring() } }
			expected := match unsafe { selector.vstring() } {
				'status' { 'q|@|:' }
				'matchOutcome' { 'I|@|:' }
				'setMatchOutcome:' { 'v|@|:|I' }
				'copyWithZone:' { '@|@|:|^{_NSZone=}' }
				else { '@|@|:' }
			}
			assert types == expected
			println('SIGNATURE ${unsafe { initialization.vstring() }} ${unsafe { selector.vstring() }} ${types} forwarded=${forwarded}')
			if selector in [c'player', c'playerID', c'lastTurnDate', c'timeoutDate', c'status', c'matchOutcome']! {
				assert msg(object, selector, 0) == 0
				println('DEFAULT ${unsafe { initialization.vstring() }} ${unsafe { selector.vstring() }} 0')
			}
		}
		for value in [u64(0), 1, 9, 0xff0000, 0xff0001, 0xffffffffffffffff, 0x8000000000000000]! {
			msg(object, c'setMatchOutcome:', value)
			assert msg(object, c'matchOutcome', 0) == u64(u32(value))
			println('OUTCOME ${unsafe { initialization.vstring() }} ${value} ${u32(value)}')
			assert msg(object, c'init', 0) == object && msg(object, c'matchOutcome', 0) == 0
		}
		println('REINIT ${unsafe { initialization.vstring() }} resets outcome')
		for selector in [c'copy', c'copyWithZone:']! {
			msg(object, c'setMatchOutcome:', 7)
			copy := msg(object, selector, 0)
			assert copy != 0 && copy != object && msg(copy, c'matchOutcome', 0) == 7
			msg(object, c'setMatchOutcome:', 8)
			assert msg(copy, c'matchOutcome', 0) == 7
			msg(copy, c'setMatchOutcome:', 9)
			assert msg(object, c'matchOutcome', 0) == 8
			msg(copy, c'release', 0)
			println('COPY ${unsafe { initialization.vstring() }} ${unsafe { selector.vstring() }} distinct independent')
		}
		msg(object, c'release', 0)
	}
	msg(pool, c'drain', 0)
	println('IOS-GKTURNBASEDPARTICIPANT-INSPECT: PASS')
}
