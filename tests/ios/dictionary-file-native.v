// SPDX-License-Identifier: GPL-2.0-or-later
// Foundation oracle. Generated XML/binary inputs and observations stay external.
module main

import os

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.dlsym(voidptr, &char) voidptr
type Send = fn (u64, u64, u64, u64, u64) u64
struct Api { send Send = unsafe { nil } }
fn (a Api) msg(object u64, name &char, x u64, y u64, z u64) u64 {
	return a.send(object, u64(C.sel_registerName(name)), x, y, z)
}
fn (a Api) string(text string) u64 {
	return a.msg(a.msg(u64(C.objc_getClass(c'NSString')), c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(text.str), u64(text.len), 4)
}
fn main() {
	assert os.args.len == 2
	root := os.real_path(os.args[1])
	assert !os.exists(root)
	os.mkdir_all(root)!
	a := Api{unsafe { Send(C.dlsym(voidptr(-2), c'objc_msgSend')) }}
	pool := a.msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0)
	defer { a.msg(pool, c'drain', 0, 0, 0) }
	values := ['<dict><key>é😀</key><string>value</string><key>array</key><array><string>x</string></array><key>dict</key><dict><key>x</key><integer>42</integer></dict><key>data</key><data>AAH/</data><key>real</key><real>1.5</real><key>bool</key><true/></dict>', '<dict/>', '<array/>', '<string>x</string>', 'malformed', 'missing', 'binary']
	for cls_name in [c'NSDictionary', c'NSMutableDictionary'] {
		cls := u64(C.objc_getClass(cls_name))
		method := C.class_getClassMethod(voidptr(cls), C.sel_registerName(c'dictionaryWithContentsOfFile:'))
		assert method != unsafe { nil }
		assert unsafe { C.method_getTypeEncoding(method).vstring() } == '@24@0:8@16'
		for i, value in values {
			path := root + '/' + i.str() + '.plist'
			if value != 'missing' {
				os.write_file(path, if value == 'malformed' { 'not a plist' } else { '<plist version="1.0">' + if value == 'binary' { values[0] } else { value } + '</plist>' })!
				if value == 'binary' {
					assert os.exec(['/usr/bin/plutil', '-convert', 'binary1', path]).exit_code == 0
					if cls_name == c'NSDictionary' { println('binary=' + os.read_bytes(path)!.hex()) }
				}
			}
			name := a.string(path)
			result := a.msg(cls, c'dictionaryWithContentsOfFile:', name, 0, 0)
			assert (result != 0) == (i in [0, 1, 6])
			if result != 0 {
				mutable := a.msg(result, c'isKindOfClass:', u64(C.objc_getClass(c'NSMutableDictionary')), 0, 0)
				assert mutable == u64(cls_name == c'NSMutableDictionary' || i == 0)
				println(unsafe { cls_name.vstring() } + ' case=' + i.str() + ' mutable=' + mutable.str())
				for key in ['array', 'dict'] {
					key_object := a.string(key)
					child := a.msg(result, c'objectForKey:', key_object, 0, 0)
					if child != 0 {
						child_mutable := a.msg(child, c'isKindOfClass:', u64(C.objc_getClass(if key == 'array' { c'NSMutableArray' } else { c'NSMutableDictionary' })), 0, 0)
						assert child_mutable == u64(key == 'array' || cls_name == c'NSMutableDictionary' || i == 0)
						println(key + ' mutable=' + child_mutable.str())
					}
					a.msg(key_object, c'release', 0, 0, 0)
				}
			}
			a.msg(name, c'release', 0, 0, 0)
		}
	}
	println('IOS-DICTIONARY-FILE-ORACLE: XML, binary, Unicode, empty, non-dictionary, malformed, missing and metadata PASS')
}
