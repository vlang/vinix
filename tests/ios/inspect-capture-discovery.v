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

type CaptureSend = fn (u64, voidptr, u64, u64, i64) u64
fn msg(object u64, selector &char, a u64, b u64, position i64) u64 {
	return unsafe { CaptureSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), a, b, position) }
}
fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/AVFoundation.framework/AVFoundation', 2) != unsafe { nil }
	cls := C.objc_getClass(c'AVCaptureDeviceDiscoverySession')
	assert cls != unsafe { nil }
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0)
	println('IMAGE ${unsafe { C.class_getImageName(cls).vstring() }}')
	println('AVCaptureDeviceDiscoverySession SIZE ${C.class_getInstanceSize(cls)} PARENT ${unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() }}')
	factory := C.class_getClassMethod(cls, C.sel_registerName(c'discoverySessionWithDeviceTypes:mediaType:position:'))
	assert factory != unsafe { nil }
	println('CLASS discoverySessionWithDeviceTypes:mediaType:position: ${unsafe { C.method_getTypeEncoding(factory).vstring() }}')
	for selector in [c'devices', c'supportedMultiCamDeviceSets']! {
		method := C.class_getInstanceMethod(cls, C.sel_registerName(selector))
		assert method != unsafe { nil }
		println('INSTANCE ${unsafe { selector.vstring() }} ${unsafe { C.method_getTypeEncoding(method).vstring() }}')
	}
	// Empty criteria request no hardware and do not request capture permission.
	types := msg(u64(C.objc_getClass(c'NSArray')), c'array', 0, 0, 0)
	session := msg(u64(cls), c'discoverySessionWithDeviceTypes:mediaType:position:', types, 0, 0)
	assert session != 0
	for selector in [c'devices', c'supportedMultiCamDeviceSets']! {
		array := msg(session, selector, 0, 0, 0)
		assert array != 0 && msg(array, c'count', 0, 0, 0) == 0
	}
	println('IOS-CAPTURE-DISCOVERY-INSPECT: empty criteria return empty device and multicam arrays')
	msg(pool, c'drain', 0, 0, 0)
}
