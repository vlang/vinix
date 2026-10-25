// SPDX-License-Identifier: GPL-2.0-or-later
// Observe native discovery without fabricating a physical device.
module main

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlopen(&char, int) voidptr
type Send = fn (u64, voidptr, u64) u64
fn msg(object u64, selector &char, argument u64) u64 {
	return unsafe { Send(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), argument) }
}
fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/GameController.framework/GameController', 2) != unsafe { nil }
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	cls := u64(C.objc_getClass(c'GCMouse')); assert cls != 0
	for _ in 0 .. 3 {
		mice := msg(cls, c'mice', 0); assert mice != 0
		count := msg(mice, c'count', 0)
		println('GCMouse mice count=' + count.str())
		println('GCMouse current nil=' + (msg(cls, c'current', 0) == 0).str())
		assert count == 0 && msg(cls, c'current', 0) == 0
	}
	for name in ['GCMouseDidConnectNotification', 'GCMouseDidDisconnectNotification',
		'GCMouseDidBecomeCurrentNotification', 'GCMouseDidStopBeingCurrentNotification']! {
		address := u64(C.dlsym(unsafe { voidptr(-2) }, name.str)); assert address != 0
		object := unsafe { *(&u64(address)) }; assert object != 0
		value := unsafe { (&char(msg(object, c'UTF8String', 0))).vstring() }
		println('CONSTANT ' + name + '=' + value); assert value == name
	}
	msg(pool, c'drain', 0)
	println('IOS-GC-MOUSE-INSPECT: empty discovery, nil current and four notification values')
}
