// SPDX-License-Identifier: GPL-2.0-or-later
// Native Foundation oracle; observations are written outside the repository.
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
	for name in [c'NSString', c'NSMutableString']! {
		cls := u64(C.objc_getClass(name))
		method := C.class_getInstanceMethod(voidptr(cls), C.sel_registerName(c'lastPathComponent'))
		println(unsafe { name.vstring() } + ' types=' + unsafe { C.method_getTypeEncoding(method).vstring() })
		for input in ['', '/', '//', '////', 'a', 'a/', '/a///', 'a//b///', '.', '..', 'a/..', 'a/.', '~', '~/file', '\\a\\b', 'C:\\a\\b', 'https://host/a?b', 'a/é😀', 'a/e\u0301', 'a\x00/b', 'a/b\x00c', '\x00', 'a/\x00/b', 'a/∕b', 'a/／b'] {
			object := a.msg(a.msg(cls, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(input.str), u64(input.len), 4)
			result := a.msg(object, c'lastPathComponent', 0, 0, 0)
			length := a.msg(result, c'lengthOfBytesUsingEncoding:', 4, 0, 0)
			bytes := a.msg(result, c'UTF8String', 0, 0, 0)
			text := unsafe { (&char(bytes)).vstring_with_len(int(length)) }
			println('input=' + input.bytes().hex() + ' result=' + text.bytes().hex())
			a.msg(object, c'release', 0, 0, 0)
		}
	}
}
