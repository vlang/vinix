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
fn C.class_getImageName(voidptr) &char
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char

type AppAttestSend = fn (u64, voidptr) u64
fn msg(object u64, selector &char) u64 {
	return unsafe { AppAttestSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector)) }
}
fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/DeviceCheck.framework/DeviceCheck', 2) != unsafe { nil }
	cls := C.objc_getClass(c'DCAppAttestService')
	assert cls != unsafe { nil }
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new')
	println('IMAGE ${unsafe { C.class_getImageName(cls).vstring() }}')
	println('DCAppAttestService SIZE ${C.class_getInstanceSize(cls)} PARENT ${unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() }}')
	method := C.class_getClassMethod(cls, C.sel_registerName(c'sharedService'))
	assert method != unsafe { nil }
	println('CLASS sharedService ${unsafe { C.method_getTypeEncoding(method).vstring() }}')
	for selector in [c'isSupported', c'generateKeyWithCompletionHandler:', c'attestKey:clientDataHash:completionHandler:', c'generateAssertion:clientDataHash:completionHandler:']! {
		instance_method := C.class_getInstanceMethod(cls, C.sel_registerName(selector))
		assert instance_method != unsafe { nil }
		println('INSTANCE ${unsafe { selector.vstring() }} ${unsafe { C.method_getTypeEncoding(instance_method).vstring() }}')
	}
	service := msg(u64(cls), c'sharedService')
	assert service != 0 && service == msg(u64(cls), c'sharedService')
	assert msg(service, c'isSupported') == 0
	println('IOS-APP-ATTEST-INSPECT: shared service, unsupported on Catalyst')
	msg(pool, c'drain')
}
