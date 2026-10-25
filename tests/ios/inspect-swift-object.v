// SPDX-License-Identifier: GPL-2.0-or-later
module main

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.object_getClass(voidptr) voidptr
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_isMetaClass(voidptr) bool
fn C.class_getInstanceSize(voidptr) usize
fn C.class_copyIvarList(voidptr, &u32) &voidptr
fn C.ivar_getName(voidptr) &char
fn C.ivar_getTypeEncoding(voidptr) &char
fn C.ivar_getOffset(voidptr) isize
fn C.objc_getProtocol(&char) voidptr
fn C.class_conformsToProtocol(voidptr, voidptr) bool
fn C.class_copyMethodList(voidptr, &u32) &voidptr
fn C.method_getName(voidptr) &char
fn C.sel_getName(voidptr) &char
fn C.method_getTypeEncoding(voidptr) &char
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr

fn main() {
	lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
	assert lib != unsafe { nil }
	cls := C.objc_getClass(c'_TtCs12_SwiftObject')
	assert cls != unsafe { nil } && !C.class_isMetaClass(cls)
	meta := C.object_getClass(cls)
	assert meta != unsafe { nil } && C.class_isMetaClass(meta)
	assert C.class_getSuperclass(cls) == unsafe { nil }
	assert C.class_getSuperclass(meta) == cls
	assert C.object_getClass(meta) == meta
	assert C.class_getInstanceSize(cls) == 16
	assert C.class_conformsToProtocol(cls, C.objc_getProtocol(c'NSObject'))
	assert C.dlsym(lib, c'OBJC_CLASS_$__TtCs12_SwiftObject') == cls
	assert C.dlsym(lib, c'OBJC_METACLASS_$__TtCs12_SwiftObject') == meta
	println('SwiftObject ROOT SIZE 16 METAPARENT SwiftObject METAISA self')
	mut ivar_count := u32(0)
	ivars := C.class_copyIvarList(cls, &ivar_count)
	mut found_isa := false
	for i in 0 .. ivar_count {
		ivar := unsafe { ivars[i] }
		if unsafe { cstring_to_vstring(C.ivar_getName(ivar)) } == 'isa' {
			assert C.ivar_getOffset(ivar) == 0
			assert unsafe { cstring_to_vstring(C.ivar_getTypeEncoding(ivar)) } == '#'
			found_isa = true
		}
		println('IVAR ${unsafe { cstring_to_vstring(C.ivar_getName(ivar)) }} ${unsafe { cstring_to_vstring(C.ivar_getTypeEncoding(ivar)) }} ${C.ivar_getOffset(ivar)}')
	}
	unsafe { free(ivars) }
	assert found_isa
	selectors := [c'class', c'superclass', c'self', c'isKindOfClass:', c'respondsToSelector:', c'conformsToProtocol:']!
	encodings := ['#16@0:8', '#16@0:8', '@16@0:8', 'B24@0:8#16', 'B24@0:8:16', 'B24@0:8@16']!
	for target in [cls, meta]! {
		for i, selector in selectors {
			method := C.class_getInstanceMethod(target, C.sel_registerName(selector))
			assert method != unsafe { nil }
			assert unsafe { cstring_to_vstring(C.method_getTypeEncoding(method)) } == encodings[i]
		}
	}
	for i, target in [cls, meta]! {
		mut count := u32(0)
		methods := C.class_copyMethodList(target, &count)
		for j in 0 .. count {
			method := unsafe { methods[j] }
			name := unsafe { cstring_to_vstring(C.sel_getName(C.method_getName(method))) }
			types := unsafe { cstring_to_vstring(C.method_getTypeEncoding(method)) }
			println('${if i == 0 { "INSTANCE" } else { "CLASS" }} ${name} ${types}')
		}
		unsafe { free(methods) }
	}
	println('IOS-SWIFT-OBJECT-INSPECT: PASS (root metadata only)')
}
