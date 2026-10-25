// SPDX-License-Identifier: GPL-2.0-or-later
// Assert the local arm64 Mac Catalyst behavior used by the compatibility shim.
module main

import os

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

struct Range { location u64; length u64 }
type Send = fn (u64, voidptr, u64, u64) u64
type RangeSend = fn (u64, voidptr) Range
type DoubleSend = fn (u64, voidptr) f64

fn msg(object u64, selector &char, a u64, b u64) u64 {
	return unsafe { Send(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), a, b) }
}

fn range_value(object u64) Range {
	return unsafe { RangeSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(c'range')) }
}

fn text(object u64) string {
	return unsafe { (&char(msg(object, c'UTF8String', 0, 0))).vstring() }
}

fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/GameKit.framework/GameKit', 2) != unsafe { nil }
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0)
	cls := C.objc_getClass(c'GKLeaderboard')
	assert C.class_getInstanceSize(cls) == 88
	assert unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() } == 'NSObject'
	println('GKLeaderboard SIZE 88 PARENT NSObject')
	if os.args.len == 3 {
		object := msg(u64(cls), c'new', 0, 0)
		msg(object, c'setRange:', os.args[1].u64(), os.args[2].u64())
		panic('invalid range was accepted')
	}
	for construction in ['init', 'new'] {
		object := if construction == 'new' { msg(u64(cls), c'new', 0, 0) } else { msg(msg(u64(cls), c'alloc', 0, 0), c'init', 0, 0) }
		assert object != 0
		for selector in [c'init', c'title', c'groupIdentifier', c'baseLeaderboardID', c'type', c'startDate', c'nextStartDate', c'duration', c'category', c'setCategory:', c'timeScope', c'setTimeScope:', c'playerScope', c'setPlayerScope:', c'identifier', c'setIdentifier:', c'range', c'setRange:', c'scores', c'maxRange', c'localPlayerScore', c'isLoading']! {
			name := unsafe { selector.vstring() }
			method := C.class_getInstanceMethod(cls, C.sel_registerName(selector))
			forwarded := name in ['title', 'groupIdentifier', 'baseLeaderboardID', 'type', 'startDate', 'nextStartDate', 'category', 'setCategory:', 'identifier', 'setIdentifier:', 'maxRange']
			assert (method == unsafe { nil }) == forwarded, name
			expected := match name {
				'type', 'timeScope', 'playerScope' { 'q16@0:8' }
				'maxRange' { 'Q16@0:8' }
				'duration' { 'd16@0:8' }
				'isLoading' { 'B16@0:8' }
				'setCategory:', 'setIdentifier:' { 'v24@0:8@16' }
				'setTimeScope:', 'setPlayerScope:' { 'v24@0:8q16' }
				'range' { '{_NSRange=QQ}16@0:8' }
				'setRange:' { 'v32@0:8{_NSRange=QQ}16' }
				else { '@16@0:8' }
			}
			if !forwarded { assert unsafe { C.method_getTypeEncoding(method).vstring() } == expected, name }
			signature := msg(object, c'methodSignatureForSelector:', u64(C.sel_registerName(selector)), 0)
			assert signature != 0, name
			mut types := unsafe { (&char(msg(signature, c'methodReturnType', 0, 0))).vstring().clone() }
			argc := msg(signature, c'numberOfArguments', 0, 0)
			for i in 0 .. argc { types += '|' + unsafe { (&char(msg(signature, c'getArgumentTypeAtIndex:', i, 0))).vstring() } }
			wanted := match name {
				'type', 'timeScope', 'playerScope' { 'q|@|:' }
				'maxRange' { 'Q|@|:' }
				'duration' { 'd|@|:' }
				'isLoading' { 'B|@|:' }
				'setCategory:', 'setIdentifier:' { 'v|@|:|@' }
				'setTimeScope:', 'setPlayerScope:' { 'v|@|:|q' }
				'range' { '{_NSRange=QQ}|@|:' }
				'setRange:' { 'v|@|:|{_NSRange=QQ}' }
				else { '@|@|:' }
			}
			assert types == wanted, name + ': ' + types
			response := msg(u64(cls), c'respondsToSelector:', u64(C.sel_registerName(selector)), 0) != 0
			assert response == (name == 'init'), name
			println('CLASS ${name} responds=${response}')
			println('SIGNATURE ${construction} ${name} ${types} forwarded=${forwarded}')
			if !name.starts_with('set') && name !in ['init', 'range', 'duration'] {
				value := msg(object, selector, 0, 0)
				assert value == if name == 'timeScope' { u64(2) } else { u64(0) }, name
				println('DEFAULT ${construction} ${name} ${value}')
			}
		}
		assert range_value(object) == Range{1, 25}
		assert unsafe { DoubleSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(c'duration')) } == 0.0
		println('DEFAULT ${construction} range {1,25} duration 0')
		for value in [u64(0), 1, 2, 3, ~u64(0)]! {
			msg(object, c'setPlayerScope:', value, 0); msg(object, c'setTimeScope:', value, 0)
			assert msg(object, c'playerScope', 0, 0) == value && msg(object, c'timeScope', 0, 0) == value
			println('SCOPES ${construction} ${value} preserved')
		}
		for value in [Range{1, 0}, Range{~u64(0), 100}, Range{5, 25}]! {
			msg(object, c'setRange:', value.location, value.length)
			assert range_value(object) == value
			println('RANGE ${construction} ${value.location} ${value.length} preserved')
		}
		value := msg(u64(C.objc_getClass(c'NSMutableString')), c'new', 0, 0)
		msg(value, c'appendString:', msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(c'hello'), 0), 0)
		msg(object, c'setIdentifier:', value, 0)
		assert msg(object, c'identifier', 0, 0) == value && msg(object, c'category', 0, 0) == value
		assert msg(object, c'baseLeaderboardID', 0, 0) == 0
		msg(value, c'appendString:', msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(c' mutated'), 0), 0)
		msg(value, c'release', 0, 0)
		assert text(msg(object, c'identifier', 0, 0)) == 'hello mutated' && text(msg(object, c'category', 0, 0)) == 'hello mutated'
		println('IDENTIFIER ${construction} retained mutable identity hello mutated; category alias')
		msg(object, c'setCategory:', 0, 0)
		assert msg(object, c'identifier', 0, 0) == 0 && msg(object, c'category', 0, 0) == 0
		println('NIL ${construction} clears identifier and category')
		other := msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(c'category'), 0)
		msg(object, c'setCategory:', other, 0)
		assert msg(object, c'identifier', 0, 0) == other && msg(object, c'category', 0, 0) == other
		println('CATEGORY ${construction} sets identifier alias')
		assert msg(object, c'init', 0, 0) == object
		assert msg(object, c'identifier', 0, 0) == 0 && msg(object, c'category', 0, 0) == 0
		assert msg(object, c'playerScope', 0, 0) == 0 && msg(object, c'timeScope', 0, 0) == 2
		assert range_value(object) == Range{1, 25}
		println('REINIT ${construction} resets identifier, category, scopes and range')
		msg(object, c'release', 0, 0)
	}
	msg(pool, c'drain', 0, 0)
	for value in [Range{0, 0}, Range{1, 101}, Range{~u64(0), ~u64(0)}]! {
		mut child := os.new_process(os.executable())
		child.set_args([value.location.str(), value.length.str()])
		child.set_redirect_stdio_merged()
		child.run()
		output := child.stdout_slurp()
		child.wait()
		code := child.code
		child.close()
		assert code == 134 && output.contains('NSRangeException'), '${code}: ${output}'
		assert output.contains('must have a location >= 1 and a range <= 100')
		println('INVALID RANGE ${value.location} ${value.length} NSRangeException exit 134')
	}
	println('IOS-GKLEADERBOARD-INSPECT: PASS')
}
