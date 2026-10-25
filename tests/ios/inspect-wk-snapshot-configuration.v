// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits

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
fn C.class_copyIvarList(voidptr, &u32) &voidptr
fn C.ivar_getName(voidptr) &char
fn C.ivar_getTypeEncoding(voidptr) &char
fn C.ivar_getOffset(voidptr) isize

struct SnapshotRect { x f64; y f64; width f64; height f64 }
type SnapshotSend = fn (u64, voidptr, u64) u64
type SnapshotRectGet = fn (u64, voidptr) SnapshotRect
type SnapshotRectSet = fn (u64, voidptr, SnapshotRect)
fn msg(object u64, selector &char, argument u64) u64 {
	return unsafe { SnapshotSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), argument) }
}
fn rect(object u64) SnapshotRect {
	return unsafe { SnapshotRectGet(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(c'rect')) }
}
fn set_rect(object u64, value SnapshotRect) {
	unsafe { SnapshotRectSet(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(c'setRect:'), value) }
}
fn main() {
	assert C.dlopen(c'/System/iOSSupport/System/Library/Frameworks/WebKit.framework/WebKit', 2) != unsafe { nil }
	cls := C.objc_getClass(c'WKSnapshotConfiguration')
	assert cls != unsafe { nil }
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	object := msg(u64(cls), c'new', 0)
	assert object != 0
	println('WKSnapshotConfiguration SIZE ${C.class_getInstanceSize(cls)} PARENT ${unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() }}')
	mut count := u32(0)
	ivars := C.class_copyIvarList(cls, &count)
	for i in 0 .. count {
		ivar := unsafe { ivars[i] }
		println('IVAR ${unsafe { C.ivar_getName(ivar).vstring() }} ${unsafe { C.ivar_getTypeEncoding(ivar).vstring() }} ${C.ivar_getOffset(ivar)}')
	}
	unsafe { free(ivars) }
	for selector in [c'init', c'copy', c'copyWithZone:', c'rect', c'setRect:', c'snapshotWidth', c'setSnapshotWidth:', c'afterScreenUpdates', c'setAfterScreenUpdates:']! {
		method := C.class_getInstanceMethod(cls, C.sel_registerName(selector))
		assert method != unsafe { nil }
		println('METHOD ${unsafe { selector.vstring() }} ${unsafe { C.method_getTypeEncoding(method).vstring() }}')
	}
	initial := rect(object)
	assert bits.f64_bits(initial.x) == 0x7ff0000000000000 && bits.f64_bits(initial.y) == 0x7ff0000000000000
	assert initial.width == 0 && initial.height == 0
	assert msg(object, c'snapshotWidth', 0) == 0 && msg(object, c'afterScreenUpdates', 0) == 1
	println('DEFAULT rect=CGRectNull snapshotWidth=nil afterScreenUpdates=YES')
	value := SnapshotRect{1.25, -2.5, 320.5, 240.25}
	set_rect(object, value)
	assert rect(object) == value
	width := msg(u64(C.objc_getClass(c'NSNumber')), c'numberWithInt:', 640)
	msg(object, c'setSnapshotWidth:', width)
	msg(object, c'setAfterScreenUpdates:', 0)
	for selector in [c'copy', c'copyWithZone:']! {
		duplicate := msg(object, selector, 0)
		assert duplicate != object && rect(duplicate) == value
		assert msg(duplicate, c'snapshotWidth', 0) == width && msg(duplicate, c'afterScreenUpdates', 0) == 0
		msg(object, c'setSnapshotWidth:', 0)
		assert msg(duplicate, c'snapshotWidth', 0) == width
		msg(object, c'setSnapshotWidth:', width)
		msg(duplicate, c'release', 0)
	}
	// Configuration setters preserve rectangles; validation belongs to capture.
	for raw in [u64(0x8000000000000000), 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000001234]! {
		v := bits.f64_from_bits(raw)
		set_rect(object, SnapshotRect{v, v, v, v})
		got := rect(object)
		assert bits.f64_bits(got.x) == raw && bits.f64_bits(got.y) == raw
		assert bits.f64_bits(got.width) == raw && bits.f64_bits(got.height) == raw
	}
	msg(object, c'setSnapshotWidth:', 0)
	assert msg(object, c'snapshotWidth', 0) == 0
	set_rect(object, value)
	msg(object, c'setSnapshotWidth:', width)
	assert msg(object, c'init', 0) == object
	reset_width := msg(object, c'snapshotWidth', 0)
	reset_after := msg(object, c'afterScreenUpdates', 0)
	assert rect(object) == initial && reset_width == width && reset_after == 1
	println('REINIT rect=CGRectNull snapshotWidth=preserved afterScreenUpdates=YES')
	msg(object, c'release', 0)
	msg(pool, c'drain', 0)
	println('IOS-WKSNAPSHOT-INSPECT: Catalyst metadata, defaults, exact rectangle bits and independent copies')
}
