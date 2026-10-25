// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only native inspection: never request microphone authorization.
module main

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.objc_getMetaClass(&char) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlopen(&char, int) voidptr
type Send = fn (u64, voidptr, u64) u64
fn msg(object u64, selector &char, argument u64) u64 {
	return unsafe { Send(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), argument) }
}
fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/AVFAudio.framework/AVFAudio', 2) != unsafe { nil }
	cls := u64(C.objc_getClass(c'AVAudioApplication'))
	assert cls != 0 && C.class_getInstanceSize(voidptr(cls)) == 24
	assert C.class_getSuperclass(voidptr(cls)) == C.objc_getClass(c'NSObject')
	assert C.dlsym(voidptr(i64(-2)), c'OBJC_CLASS_$_AVAudioApplication') == voidptr(cls)
	assert C.dlsym(voidptr(i64(-2)), c'OBJC_METACLASS_$_AVAudioApplication') == C.objc_getMetaClass(c'AVAudioApplication')
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	object := msg(cls, c'sharedInstance', 0)
	assert object != 0
	for _ in 0 .. 3 {
		assert msg(cls, c'sharedInstance', 0) == object
		permission := msg(object, c'recordPermission', 0)
		assert permission in [u64(0x756e6474), 0x64656e79, 0x67726e74]!
		muted := u8(msg(object, c'isInputMuted', 0))
		assert muted <= 1
		println('AVAudioApplication recordPermission=' + permission.hex() + ' isInputMuted=' + muted.str())
	}
	msg(pool, c'drain', 0)
	println('IOS-AUDIO-APPLICATION-INSPECT: 24-byte NSObject singleton, scoped native symbols and read-only permission and mute queries')
}
