// SPDX-License-Identifier: GPL-2.0-or-later
module main

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.object_getClass(voidptr) voidptr
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_isMetaClass(voidptr) bool
fn C.dlopen(&char, int) voidptr

fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/GameKit.framework/GameKit', 2) != unsafe { nil }
	nav := C.objc_getClass(c'UINavigationController')
	view := C.objc_getClass(c'UIViewController')
	assert nav != unsafe { nil } && view != unsafe { nil }
	assert C.class_getSuperclass(nav) == view
	assert C.class_getSuperclass(C.object_getClass(nav)) == C.object_getClass(view)
	for name in [c'GKGameCenterViewController', c'GKTurnBasedMatchmakerViewController']! {
		cls := C.objc_getClass(name)
		assert cls != unsafe { nil } && !C.class_isMetaClass(cls)
		meta := C.object_getClass(cls)
		assert meta != unsafe { nil } && C.class_isMetaClass(meta)
		assert C.class_getSuperclass(cls) == nav
		assert C.class_getSuperclass(meta) == C.object_getClass(nav)
		println('${unsafe { name.vstring() }} PARENT UINavigationController METAPARENT UINavigationController')
	}
	println('UINavigationController PARENT UIViewController METAPARENT UIViewController')
	println('IOS-GKMATCHMAKER-INSPECT: PASS (metadata only; no UI construction)')
}
