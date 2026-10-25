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
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.class_copyIvarList(voidptr, &u32) &voidptr
fn C.ivar_getName(voidptr) &char
fn C.ivar_getTypeEncoding(voidptr) &char
fn C.ivar_getOffset(voidptr) isize

type EventControllerSend = fn (u64, voidptr, u64, u64) u64
fn msg(object u64, selector &char, argument u64) u64 {
	return unsafe { EventControllerSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), argument, 0) }
}
fn main() {
	assert C.dlopen(c'/System/iOSSupport/System/Library/Frameworks/UIKit.framework/UIKit', 2) != unsafe { nil }
	assert C.dlopen(c'/System/iOSSupport/System/Library/Frameworks/GameController.framework/GameController', 2) != unsafe { nil }
	cls := C.objc_getClass(c'GCEventViewController')
	assert cls != unsafe { nil }
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	println('IMAGE ${unsafe { C.class_getImageName(cls).vstring() }}')
	ui := C.objc_getClass(c'UIViewController')
	println('UIViewController SIZE ${C.class_getInstanceSize(ui)} PARENT ${unsafe { C.class_getName(C.class_getSuperclass(ui)).vstring() }}')
	println('GCEventViewController SIZE ${C.class_getInstanceSize(cls)} PARENT ${unsafe { C.class_getName(C.class_getSuperclass(cls)).vstring() }}')
	mut count := u32(0)
	ivars := C.class_copyIvarList(cls, &count)
	for i in 0 .. count {
		ivar := unsafe { ivars[i] }
		println('IVAR ${unsafe { C.ivar_getName(ivar).vstring() }} ${unsafe { C.ivar_getTypeEncoding(ivar).vstring() }} ${C.ivar_getOffset(ivar)}')
	}
	unsafe { free(ivars) }
	for selector in [c'init', c'initWithNibName:bundle:', c'controllerUserInteractionEnabled', c'setControllerUserInteractionEnabled:']! {
		method := C.class_getInstanceMethod(cls, C.sel_registerName(selector))
		assert method != unsafe { nil }
		println('METHOD ${unsafe { selector.vstring() }} ${unsafe { C.method_getTypeEncoding(method).vstring() }}')
	}
	for selector in [c'new', c'init', c'initWithNibName:bundle:']! {
		allocated := if selector == c'new' { u64(cls) } else { msg(u64(cls), c'alloc', 0) }
		object := msg(allocated, selector, 0)
		assert object != 0 && msg(object, c'controllerUserInteractionEnabled', 0) == 0
		msg(object, c'setControllerUserInteractionEnabled:', 1)
		assert msg(object, c'controllerUserInteractionEnabled', 0) == 1
		assert msg(object, c'init', 0) == object
		assert msg(object, c'controllerUserInteractionEnabled', 0) == 1
		println('REINIT ${unsafe { selector.vstring() }} enabled=${msg(object, c'controllerUserInteractionEnabled', 0)}')
		msg(object, c'setControllerUserInteractionEnabled:', 0)
		assert msg(object, c'controllerUserInteractionEnabled', 0) == 0
		msg(object, c'release', 0)
	}
	msg(pool, c'drain', 0)
	println('IOS-GCEVENT-INSPECT: Catalyst metadata, default NO, mutation and initialization')
}
