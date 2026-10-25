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

type PlayerSend = fn (u64, voidptr, u64, u64) u64
fn msg(object u64, selector &char, a u64) u64 {
	return unsafe { PlayerSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), a, 0) }
}
fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/GameKit.framework/GameKit', 2) != unsafe { nil }
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	for name in [c'GKBasePlayer', c'GKPlayer']! {
		cls := C.objc_getClass(name)
		base := name == c'GKBasePlayer'
		assert cls != unsafe { nil } && C.class_getInstanceSize(cls) == if base { usize(8) } else { usize(32) }
		parent := unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() }
		assert parent == if base { 'NSObject' } else { 'GKBasePlayer' }
		println('${unsafe { name.vstring() }} SIZE ${C.class_getInstanceSize(cls)} PARENT ${parent}')
		for initialization in [c'init', c'new']! {
			object := if initialization == c'new' { msg(u64(cls), initialization, 0) } else { msg(msg(u64(cls), c'alloc', 0), initialization, 0) }
			assert object != 0
			for selector in [c'playerID', c'displayName', c'alias', c'guestIdentifier', c'isFriend', c'isInvitable', c'scopedIDsArePersistent']! {
				if base && selector !in [c'playerID', c'displayName']! {
					assert msg(object, c'respondsToSelector:', u64(C.sel_registerName(selector))) == 0
					println('UNAVAILABLE GKBasePlayer ${unsafe { selector.vstring() }}')
					continue
				}
				method := C.class_getInstanceMethod(cls, C.sel_registerName(selector))
				forwarded := selector in [c'guestIdentifier', c'isFriend']!
				assert (method == unsafe { nil }) == forwarded
				boolean := selector in [c'isFriend', c'isInvitable', c'scopedIDsArePersistent']!
				expected := if boolean { 'B16@0:8' } else { '@16@0:8' }
				if !forwarded { assert unsafe { C.method_getTypeEncoding(method).vstring() } == expected }
				signature := msg(object, c'methodSignatureForSelector:', u64(C.sel_registerName(selector)))
				assert signature != 0 && msg(signature, c'numberOfArguments', 0) == 2
				mut types := unsafe { (&char(msg(signature, c'methodReturnType', 0))).vstring().clone() }
				for i in 0 .. u64(2) { types += unsafe { (&char(msg(signature, c'getArgumentTypeAtIndex:', i))).vstring() } }
				assert types == if boolean { 'B@:' } else { '@@:' }
				value := msg(object, selector, 0)
				text := if selector == c'alias' { unsafe { (&char(msg(value, c'UTF8String', 0))).vstring().clone() } } else { value.str() }
				assert text == if selector == c'alias' { 'Unknown' } else { '0' }
				println('DEFAULT ${unsafe { name.vstring() }} ${unsafe { initialization.vstring() }} ${unsafe { selector.vstring() }} ${types} ${text}')
			}
			copy_method := C.class_getInstanceMethod(cls, C.sel_registerName(c'copyWithZone:'))
			assert unsafe { C.method_getTypeEncoding(copy_method).vstring() } == '@24@0:8^{_NSZone=}16'
			for selector in [c'copy', c'copyWithZone:']! {
				refs := msg(object, c'retainCount', 0)
				assert msg(object, selector, 0) == object
				assert msg(object, c'retainCount', 0) == refs + 1
				msg(object, c'release', 0)
				println('COPY ${unsafe { name.vstring() }} ${unsafe { initialization.vstring() }} ${unsafe { selector.vstring() }} self retained')
			}
			assert msg(object, c'init', 0) == object
			msg(object, c'release', 0)
		}
	}
	msg(pool, c'drain', 0)
	println('IOS-GKPLAYER-INSPECT: PASS')
}
