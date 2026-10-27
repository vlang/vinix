// SPDX-License-Identifier: GPL-2.0-or-later
// Native Foundation observations; write generated output outside the repository.
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
	mut pairs := 0
	mut long_inputs := 0
	for name in [c'NSString', c'NSMutableString']! {
		cls := u64(C.objc_getClass(name))
		method := C.class_getInstanceMethod(voidptr(cls), C.sel_registerName(c'stringByAppendingPathComponent:'))
		assert method != unsafe { nil }
		assert unsafe { C.method_getTypeEncoding(method).vstring() } == '@24@0:8@16'
		println(unsafe { name.vstring() } + ' types=' + unsafe { C.method_getTypeEncoding(method).vstring() })
		for input in ['', '/', '//', '////', 'a', 'a/', '/a///', 'a//b///', '.', '..',
			'a/..', 'a/.', '~', '~/file', '\\a\\b', 'C:\\a\\b', 'https://host/a?b',
			'a/é😀', 'a/e\u0301', 'a\x00/b', 'a/b\x00c', '\x00', 'a/∕b', 'a/／b'] {
			object := a.msg(a.msg(cls, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(input.str), u64(input.len), 4)
			for component in ['', '/', '//', 'b', '/b', 'b/', '/b//c///', '.', '..',
				'../b', '~', '~/file', '\\b', 'é😀', 'e\u0301', '\x00', 'b\x00c', '∕b', '／b'] {
				other := a.msg(a.msg(cls, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(component.str), u64(component.len), 4)
				result := a.msg(object, c'stringByAppendingPathComponent:', other, 0, 0)
				assert (result == 0) == (input.contains('\x00') || component.contains('\x00'))
				length := a.msg(result, c'lengthOfBytesUsingEncoding:', 4, 0, 0)
				bytes := a.msg(result, c'UTF8String', 0, 0, 0)
				text := unsafe { (&char(bytes)).vstring_with_len(int(length)) }
				println('input=' + input.bytes().hex() + ' component=' + component.bytes().hex() + ' nil=${result == 0} result=' + text.bytes().hex())
				pairs++
				a.msg(other, c'release', 0, 0, 0)
			}
			a.msg(object, c'release', 0, 0, 0)
		}
		for size in [1023, 1024, 4095, 4096, 8192, 65536] {
			for input in ['a'.repeat(size), '/'.repeat(size), 'é😀'.repeat(size)] {
				object := a.msg(a.msg(cls, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(input.str), u64(input.len), 4)
				other := a.msg(a.msg(cls, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(c'/b//c/'), 6, 4)
				result := a.msg(object, c'stringByAppendingPathComponent:', other, 0, 0)
				length := a.msg(result, c'lengthOfBytesUsingEncoding:', 4, 0, 0)
				assert result != 0 && length == u64(if input[0] == `/` { 4 } else { input.len + 4 })
				println('long input=${input.len} root=${input[0] == `/`} nil=${result == 0} result_bytes=${length}')
				long_inputs++
				a.msg(other, c'release', 0, 0, 0)
				a.msg(object, c'release', 0, 0, 0)
			}
		}
	}
	assert pairs == 912 && long_inputs == 36
	println('IOS-STRING-APPEND-PATH-ORACLE: 912 input pairs, 36 long inputs and two class signatures PASS')
}
