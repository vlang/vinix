// SPDX-License-Identifier: GPL-2.0-or-later
// Native Foundation observations; generated output belongs outside Git.
module main

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.dlsym(voidptr, &char) voidptr
type Send = fn (u64, u64, u64, u64, u64) u64
struct Api { send Send = unsafe { nil } }
fn (a Api) msg(object u64, name &char, x u64, y u64, z u64) u64 {
	return a.send(object, u64(C.sel_registerName(name)), x, y, z)
}
fn main() {
	a := Api{unsafe { Send(C.dlsym(voidptr(-2), c'objc_msgSend')) }}
	pool := a.msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0)
	defer { a.msg(pool, c'drain', 0, 0, 0) }
	mut cases := 0
	for name in [c'NSString', c'NSMutableString']! {
		cls := u64(C.objc_getClass(name))
		method := C.class_getInstanceMethod(voidptr(cls), C.sel_registerName(c'getCString:maxLength:encoding:'))
		assert method != unsafe { nil }
		assert unsafe { C.method_getTypeEncoding(method).vstring() } == 'B40@0:8*16Q24Q32'
		println(unsafe { name.vstring() } + ' types=' + unsafe { C.method_getTypeEncoding(method).vstring() })
		for input in ['', 'ABC', 'A\x00B', 'é', 'AéB', 'A😀B', 'A€B',
			'e\u0301', 'Ae\u0301B', 'Ae\u0301\u0300B', 'A\u030aB', '\u0080ÿ\x00é',
			'\u212b', '\u212a', 'e\u0341', '\u0301'] {
			object := a.msg(a.msg(cls, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(input.str), u64(input.len), 4)
			for encoding in [u64(1), 4, 5]! {
				for capacity in 0 .. input.len + 3 {
					mut buffer := []u8{len: input.len + 7, init: 0xa5}
					result := a.msg(object, c'getCString:maxLength:encoding:', u64(unsafe { &buffer[2] }), u64(capacity), encoding)
					assert buffer[0] == 0xa5 && buffer[1] == 0xa5
					// Observe short-buffer behavior in ample physical storage:
					// native UTF8 capacity=1 can report success beyond the bound.
					for i in input.len + 5 .. buffer.len { assert buffer[i] == 0xa5 }
					println('input=' + input.bytes().hex() + ' enc=${encoding} cap=${capacity} result=${result & 0xff} bytes=' + buffer.hex())
					cases++
					unsafe { buffer.free() }
				}
			}
			a.msg(object, c'release', 0, 0, 0)
		}
	}
	assert cases == 648
	println('IOS-STRING-GET-CSTRING-ORACLE: ${cases} conversion observations and two class signatures PASS')
}
