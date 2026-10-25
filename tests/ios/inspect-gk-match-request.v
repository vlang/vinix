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

type MatchSend = fn (u64, voidptr, u64, u64) u64
fn msg(object u64, selector &char, a u64) u64 {
	return unsafe { MatchSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), a, 0) }
}
fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/GameKit.framework/GameKit', 2) != unsafe { nil }
	cls := C.objc_getClass(c'GKMatchRequest')
	assert cls != unsafe { nil }
	assert C.class_getInstanceSize(cls) == 40
	assert unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() } == 'NSObject'
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	println('GKMatchRequest SIZE ${C.class_getInstanceSize(cls)} PARENT ${unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() }}')
	for selector in [c'init', c'minPlayers', c'setMinPlayers:', c'maxPlayers', c'setMaxPlayers:', c'playerGroup', c'setPlayerGroup:', c'playerAttributes', c'setPlayerAttributes:', c'defaultNumberOfPlayers', c'setDefaultNumberOfPlayers:', c'restrictToAutomatch', c'setRestrictToAutomatch:', c'recipients', c'setRecipients:', c'playersToInvite', c'setPlayersToInvite:', c'copyWithZone:']! {
		method := C.class_getInstanceMethod(cls, C.sel_registerName(selector))
		if method != unsafe { nil } {
			println('INSTANCE ${unsafe { selector.vstring() }} ${unsafe { C.method_getTypeEncoding(method).vstring() }}')
		} else { println('ABSENT ${unsafe { selector.vstring() }}') }
	}
	object := msg(u64(cls), c'new', 0)
	assert object != 0
	getters := [c'minPlayers', c'maxPlayers', c'playerGroup', c'playerAttributes', c'defaultNumberOfPlayers', c'restrictToAutomatch']!
	setters := [c'setMinPlayers:', c'setMaxPlayers:', c'setPlayerGroup:', c'setPlayerAttributes:', c'setDefaultNumberOfPlayers:', c'setRestrictToAutomatch:']!
	defaults := [u64(2), 2, 1, 0xffffffff, 0, 0]!
	for i, getter in getters {
		value := msg(object, getter, 0)
		assert value == defaults[i]
		println('DEFAULT ${unsafe { getter.vstring() }} ${value}')
	}
	for i, setter in setters {
		for value in [u64(0), 1, 7, 0x100000001, 0xffffffffffffffff]! {
			msg(object, setter, value)
			actual := msg(object, getters[i], 0)
			expected := if i == 2 { value } else if i == 3 { u64(u32(value)) } else { u64(u8(value)) }
			assert actual == expected
			println('SET ${unsafe { setter.vstring() }} ${value} -> ${actual}')
		}
	}
	for i, getter in getters {
		for j, selector in [getter, setters[i]]! {
			signature := msg(object, c'methodSignatureForSelector:', u64(C.sel_registerName(selector)))
			assert signature != 0
			mut encoding := unsafe { (&char(msg(signature, c'methodReturnType', 0))).vstring().clone() }
			for index in 0 .. msg(signature, c'numberOfArguments', 0) {
				encoding += ' ' + unsafe { (&char(msg(signature, c'getArgumentTypeAtIndex:', index))).vstring() }
			}
			type_code := ['C', 'C', 'Q', 'I', 'C', 'B']![i]
			assert encoding == if j == 0 { type_code + ' @ :' } else { 'v @ : ' + type_code }
			println('SIGNATURE ${unsafe { selector.vstring() }} ${encoding}')
		}
	}
	msg(object, c'setMinPlayers:', 2)
	msg(object, c'setMaxPlayers:', 8)
	msg(object, c'setPlayerGroup:', 77)
	msg(object, c'setPlayerAttributes:', 0)
	msg(object, c'setDefaultNumberOfPlayers:', 0)
	assert msg(object, c'minPlayers', 0) == 2 && msg(object, c'maxPlayers', 0) == 8
	assert msg(object, c'defaultNumberOfPlayers', 0) == 0 && msg(object, c'playerAttributes', 0) == 0
	println('COUNTS min=${msg(object, c'minPlayers', 0)} max=${msg(object, c'maxPlayers', 0)} default=${msg(object, c'defaultNumberOfPlayers', 0)} attributes=${msg(object, c'playerAttributes', 0)}')
	assert msg(object, c'init', 0) == object
	for i, getter in getters {
		assert msg(object, getter, 0) == defaults[i]
		println('REINIT ${unsafe { getter.vstring() }} ${defaults[i]}')
	}
	msg(object, c'release', 0)
	msg(pool, c'drain', 0)
	println('IOS-GKMATCHREQUEST-INSPECT: PASS')
}
