// SPDX-License-Identifier: GPL-2.0-or-later
// Native Foundation observations for the NUL-terminated string factory.
module main

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.object_getClass(voidptr) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.dlsym(voidptr, &char) voidptr
type Send = fn (u64, u64, u64, u64) u64

fn main() {
	send := unsafe { Send(C.dlsym(voidptr(-2), c'objc_msgSend')) }
	pool := send(u64(C.objc_getClass(c'NSAutoreleasePool')), u64(C.sel_registerName(c'new')), 0, 0)
	for name in ['NSString', 'NSMutableString'] {
		cls := C.objc_getClass(name.str)
		sel := C.sel_registerName(c'stringWithCString:encoding:')
		method := C.class_getInstanceMethod(C.object_getClass(cls), sel)
		assert method != unsafe { nil }
		println('CSTRING-NATIVE: class=${name} types=' + unsafe { C.method_getTypeEncoding(method).vstring() })
		for encoding in [u64(1), 4] {
			for value in 1 .. 256 {
				bytes := [u8(value), 0]!
				result := send(u64(cls), u64(sel), u64(unsafe { &bytes[0] }), encoding)
				text := if result == 0 { 'nil' } else { unsafe { (&char(voidptr(send(result, u64(C.sel_registerName(c'UTF8String')), 0, 0)))).vstring().bytes().hex() } }
				println('CSTRING-NATIVE: class=${name} encoding=${encoding} input=${value:02x} output=${text}')
			}
		}
		for input in ['efbbbf41', 'efbbbfefbbbf41', '41efbbbf42', 'c3a9f09f9880',
			'c080', 'eda080', 'f4908080', 'e282', 'a9a9', '41a9', 'a941', 'efbbbfa9',
			'c2', 'c2a9', 'c2a9a9', 'a9c2a9', 'a980', 'c3a9ff'] {
			mut bytes := []u8{}
			for i := 0; i < input.len; i += 2 { bytes << u8(input[i..i + 2].parse_uint(16, 8) or { panic(err) }) }
			bytes << 0
			result := send(u64(cls), u64(sel), u64(bytes.data), 4)
			text := if result == 0 { 'nil' } else { unsafe { (&char(voidptr(send(result, u64(C.sel_registerName(c'UTF8String')), 0, 0)))).vstring().bytes().hex() } }
			println('CSTRING-NATIVE: class=${name} encoding=4 input=${input} output=${text}')
		}
	}
	send(pool, u64(C.sel_registerName(c'drain')), 0, 0)
}
