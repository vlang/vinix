// SPDX-License-Identifier: GPL-2.0-or-later
// Native Foundation oracle; generated observations stay outside the repository.
module main

import os

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
#include <sys/xattr.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.dlsym(voidptr, &char) voidptr
fn C.listxattr(&char, &char, usize, int) i64
fn C.getxattr(&char, &char, voidptr, usize, u32, int) i64

type Send = fn (u64, u64, u64, u64, u64) u64
struct Api { send Send = unsafe { nil } }
fn (a Api) msg(object u64, name &char, x u64, y u64, z u64) u64 {
	return a.send(object, u64(C.sel_registerName(name)), x, y, z)
}
fn (a Api) cls(name &char) u64 { return u64(C.objc_getClass(name)) }
fn (a Api) string_object(text string) u64 { return a.msg(a.cls(c'NSString'), c'stringWithUTF8String:', u64(text.str), 0, 0) }
fn (a Api) text(object u64) string {
	if object == 0 { return '<nil>' }
	return unsafe { (&char(a.msg(object, c'UTF8String', 0, 0, 0))).vstring() }
}
fn (a Api) describe(error_object u64) string {
	if error_object == 0 { return '<nil>' }
	return a.text(a.msg(error_object, c'description', 0, 0, 0))
}
fn main() {
	if os.args.len != 2 || !os.is_abs_path(os.args[1]) { panic('usage: url-resource-native EXTERNAL_DIRECTORY') }
	out := os.args[1]
	os.mkdir_all(out)!
	a := Api{unsafe { Send(C.dlsym(voidptr(-2), c'objc_msgSend')) }}
	pool := a.msg(a.cls(c'NSAutoreleasePool'), c'new', 0, 0, 0)
	defer { a.msg(pool, c'drain', 0, 0, 0) }
	method := C.class_getInstanceMethod(voidptr(a.cls(c'NSURL')), C.sel_registerName(c'setResourceValue:forKey:error:'))
	println('types=' + unsafe { C.method_getTypeEncoding(method).vstring() })
	key := unsafe { *(&u64(C.dlsym(voidptr(-2), c'NSURLIsExcludedFromBackupKey'))) }
	file := out + '/file'
	os.write_file(file, 'original')!
	os.mkdir_all(out + '/directory')!
	os.symlink(file, out + '/link')!
	os.symlink(out + '/missing', out + '/dangling')!
	for path in [file, out + '/directory', out + '/link', out + '/dangling', out + '/missing', 'https://example.invalid/file'] {
		url := a.msg(a.cls(c'NSURL'), if path.starts_with('https:') { c'URLWithString:' } else { c'fileURLWithPath:' }, a.string_object(path), 0, 0)
		for flag in [0, 1, 0] {
			value := a.msg(a.cls(c'NSNumber'), c'numberWithBool:', u64(flag), 0, 0)
			mut error_object := u64(0)
			ok := a.msg(url, c'setResourceValue:forKey:error:', value, key, u64(unsafe { &error_object }))
			mut read_value := u64(0)
			mut read_error := u64(0)
			read_ok := a.msg(url, c'getResourceValue:forKey:error:', u64(unsafe { &read_value }), key, u64(unsafe { &read_error }))
			println('path=${path} flag=${flag} ok=${ok} error=' + a.describe(error_object) + ' read=${read_ok}/' + a.describe(read_value) + ' read_error=' + a.describe(read_error))
			mut names := [4096]u8{}
			length := C.listxattr(path.str, unsafe { &char(&names[0]) }, 4096, 0)
			if length > 0 {
				for name in unsafe { names[..int(length)].bytestr() }.split('\x00').filter(it != '') {
					mut bytes := [1024]u8{}
					n := C.getxattr(path.str, name.str, unsafe { &bytes[0] }, 1024, 0, 0)
					println('xattr=${name} bytes=' + if n < 0 { 'error' } else { bytes[..int(n)].hex() })
				}
			}
		}
		for other in ['NSURLFileSizeKey', 'UnrecognizedResourceKey'] {
			mut error_object := u64(0)
			ok := a.msg(url, c'setResourceValue:forKey:error:', a.msg(a.cls(c'NSNumber'), c'numberWithBool:', 1, 0, 0), a.string_object(other), u64(unsafe { &error_object }))
			println('path=${path} key=${other} ok=${ok} error=' + a.describe(error_object))
		}
	}
	url := a.msg(a.cls(c'NSURL'), c'fileURLWithPath:', a.string_object(file), 0, 0)
	for value in [u64(0), a.string_object('YES'), a.string_object('NO'), a.string_object('0'), a.string_object('1'), a.string_object('  YES'), a.string_object('false'), a.string_object('true'), a.string_object('+1'), a.string_object('-1'), a.string_object('0001'), a.string_object('0x1'), a.string_object('0Y'), a.string_object('+YES'), a.string_object('01no'), a.string_object('1.0'), a.string_object('0.1')] {
		mut error_object := u64(0x12345678)
		ok := a.msg(url, c'setResourceValue:forKey:error:', value, key, u64(unsafe { &error_object }))
		mut bytes := [1024]u8{}
		n := C.getxattr(file.str, c'com.apple.metadata:com_apple_backup_excludeItem', unsafe { &bytes[0] }, 1024, 0, 0)
		println('extra value=' + a.describe(value) + ' ok=${ok} error_untouched=${error_object == 0x12345678} excluded=${n > 0}')
	}
}
