// SPDX-License-Identifier: GPL-2.0-or-later
// Native UIKit data-export oracle, without requiring an iOS SDK.
module main

#flag -framework CoreFoundation
#include <CoreFoundation/CFString.h>
#include <dlfcn.h>
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) int
fn C.CFGetTypeID(voidptr) u64
fn C.CFStringGetTypeID() u64
fn C.CFStringGetCString(voidptr, &char, i64, u32) bool

fn main() {
	path := '/System/iOSSupport/System/Library/Frameworks/UIKit.framework/UIKit'
	library := C.dlopen(path.str, C.RTLD_NOW | C.RTLD_LOCAL)
	assert library != unsafe { nil }
	defer { C.dlclose(library) }
	println('UIKIT: ' + path)
	for name in ['UISceneWillEnterForegroundNotification', 'UISceneDidEnterBackgroundNotification']! {
		cell := C.dlsym(library, name.str)
		assert cell != unsafe { nil }
		object := unsafe { *(&voidptr(cell)) }
		assert C.CFGetTypeID(object) == C.CFStringGetTypeID()
		mut buffer := [256]u8{}
		assert C.CFStringGetCString(object, unsafe { &char(&buffer[0]) }, 256, 0x08000100)
		value := unsafe { tos_clone(&buffer[0]) }
		println('IOS-SCENE-NATIVE: ' + name + '=' + value)
		assert value == name
	}
}
