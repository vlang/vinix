// SPDX-License-Identifier: GPL-2.0-or-later
module main

#flag -framework Foundation
#include <objc/runtime.h>
fn C.objc_getClass(&char) voidptr
fn C.object_getClass(voidptr) voidptr
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_isMetaClass(voidptr) bool
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.sel_registerName(&char) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.class_getInstanceVariable(voidptr, &char) voidptr
fn C.ivar_getOffset(voidptr) isize
fn C.ivar_getTypeEncoding(voidptr) &char
fn C.objc_getProtocol(&char) voidptr
fn C.class_conformsToProtocol(voidptr, voidptr) bool

fn main() {
	cls := C.objc_getClass(c'NSProxy')
	assert cls != unsafe { nil } && !C.class_isMetaClass(cls)
	meta := C.object_getClass(cls)
	assert meta != unsafe { nil } && C.class_isMetaClass(meta)
	assert C.class_getSuperclass(cls) == unsafe { nil }
	assert C.class_getSuperclass(meta) == cls
	assert C.object_getClass(meta) == meta
	assert C.class_getInstanceSize(cls) == 8
	ivar := C.class_getInstanceVariable(cls, c'isa')
	assert ivar != unsafe { nil } && C.ivar_getOffset(ivar) == 0
	assert unsafe { cstring_to_vstring(C.ivar_getTypeEncoding(ivar)) } == '#'
	assert C.class_conformsToProtocol(cls, C.objc_getProtocol(c'NSObject'))
	selectors := ['class', 'superclass', 'self', 'isKindOfClass:', 'respondsToSelector:', 'conformsToProtocol:']!
	encodings := ['#16@0:8', '#16@0:8', '@16@0:8', 'B24@0:8#16', 'B24@0:8:16', 'B24@0:8@16']!
	for i, selector in selectors {
		for target in [cls, meta]! {
			method := C.class_getInstanceMethod(target, C.sel_registerName(selector.str))
			assert method != unsafe { nil }
			assert unsafe { cstring_to_vstring(C.method_getTypeEncoding(method)) } == encodings[i]
		}
	}
	println('NSProxy SIZE ${C.class_getInstanceSize(cls)} ROOT class-parent=nil meta-parent=class meta-isa=meta')
	for selector in ['class', 'superclass', 'self', 'isKindOfClass:', 'respondsToSelector:',
		'conformsToProtocol:', 'alloc', 'new', 'init', 'forwardInvocation:',
		'methodSignatureForSelector:', 'copy']! {
		for is_meta in [false, true]! {
			method := C.class_getInstanceMethod(if is_meta { meta } else { cls }, C.sel_registerName(selector.str))
			types := if method == unsafe { nil } { 'absent' } else { unsafe { cstring_to_vstring(C.method_getTypeEncoding(method)) } }
			println('${if is_meta { "+" } else { "-" }}${selector} ${types}')
		}
	}
	println('IOS-NSPROXY-INSPECT: PASS (root metadata only; no proxy construction)')
}
