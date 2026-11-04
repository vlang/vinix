// SPDX-License-Identifier: GPL-2.0-or-later
module main
#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.dlsym(voidptr, &char) voidptr
fn C.dlopen(&char, int) voidptr
type DeviceSend = fn (u64, u64, u64) u64
fn message(object u64, selector &char, arg u64) u64 {
	return unsafe { DeviceSend(C.dlsym(voidptr(-2), c'objc_msgSend'))(object, u64(C.sel_registerName(selector)), arg) }
}
fn main() {
	assert C.dlopen(c'/System/iOSSupport/System/Library/Frameworks/UIKit.framework/UIKit', 2) != unsafe { nil }
	pool := message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	cls := C.objc_getClass(c'UIDevice')
	device := message(u64(cls), c'currentDevice', 0)
	getter := C.class_getInstanceMethod(cls, C.sel_registerName(c'_feedbackSupportLevel'))
	if getter != unsafe { nil } { println('getter type=' + unsafe { cstring_to_vstring(C.method_getTypeEncoding(getter)) }) }
	for name in ['_feedbackSupportLevel', 'feedbackSupportLevel']! {
		key := message(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(name.str))
		value := message(device, c'valueForKey:', key)
		println('${name}: value=${i64(message(value, c'longLongValue', 0))} NSNumber=${message(value, c'isKindOfClass:', u64(C.objc_getClass(c'NSNumber')))} objCType=' + unsafe { cstring_to_vstring(&char(message(value, c'objCType', 0))) })
	}
	message(pool, c'drain', 0)
}
