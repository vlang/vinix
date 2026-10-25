// SPDX-License-Identifier: GPL-2.0-or-later
// Native no-controller discovery and notification constants. No device is fabricated.
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
	cls := u64(C.objc_getClass(c'GCController'))
	assert cls != 0
	for _ in 0 .. 3 {
		controllers := msg(cls, c'controllers', 0)
		assert controllers != 0
		println('GCController controllers count=' + msg(controllers, c'count', 0).str())
		println('GCController current nil=' + (msg(cls, c'current', 0) == 0).str())
		println('GCController shouldMonitorBackgroundEvents=' + msg(cls, c'shouldMonitorBackgroundEvents', 0).str())
	}
	for value in [u64(1), 0, 1, 0]! {
		msg(cls, c'setShouldMonitorBackgroundEvents:', value)
		println('GCController set background=' + value.str() + ' read=' + msg(cls, c'shouldMonitorBackgroundEvents', 0).str())
	}
	for name in ['GCControllerDidBecomeCurrentNotification', 'GCControllerDidConnectNotification', 'GCControllerDidDisconnectNotification']! {
		address := u64(C.dlsym(voidptr(i64(-2)), name.str))
		assert address != 0
		value := unsafe { *(&u64(address)) }
		assert value != 0
		println('CONSTANT ' + name + '=' + unsafe { (&char(msg(value, c'UTF8String', 0))).vstring() })
	}
	msg(pool, c'drain', 0)
}
