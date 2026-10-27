// SPDX-License-Identifier: GPL-2.0-or-later
// Native Foundation oracle; observations and synthetic bundles stay outside Git.
module main

import os

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
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
	values := ['<string>org.vinix.example</string>', '<string></string>', '<string>é😀&amp;é</string>', '<integer>42</integer>', '<true/>', '<array><string>x</string></array>', '<dict><key>x</key><string>y</string></dict>', '', 'malformed', 'missing', 'binary']
	for i, value in values {
		path := os.join_path(root, i.str() + '.bundle')
		os.mkdir_all(path)!
		plist_path := path + '/Info.plist'
		if value != 'missing' {
			text := if value == 'malformed' { 'not a plist' } else { '<?xml version="1.0"?><plist version="1.0"><dict>' + if value == '' { '' } else { '<key>CFBundleIdentifier</key>' + if value == 'binary' { '<string>org.vinix.binary</string>' } else { value } } + '</dict></plist>' }
			os.write_file(plist_path, text)!
			if value == 'binary' {
				assert os.exec(['/usr/bin/plutil', '-convert', 'binary1', plist_path]).exit_code == 0
				println('binary=' + os.read_bytes(plist_path)!.hex())
			}
		}
		name := a.string(path)
		bundle := a.msg(u64(C.objc_getClass(c'NSBundle')), c'bundleWithPath:', name, 0, 0)
		result := a.msg(bundle, c'bundleIdentifier', 0, 0, 0)
		mut output := 'nil'
		if result != 0 {
			is_string := a.msg(result, c'isKindOfClass:', u64(C.objc_getClass(c'NSString')), 0, 0)
			if is_string == 1 {
				len := a.msg(result, c'lengthOfBytesUsingEncoding:', 4, 0, 0)
				output = 'string:' + unsafe { (&char(a.msg(result, c'UTF8String', 0, 0, 0))).vstring_with_len(int(len)) }.bytes().hex()
			} else { output = 'non-string' }
		}
		assert bundle != 0
		assert output == match i {
			0 { 'string:' + 'org.vinix.example'.bytes().hex() }
			1 { 'string:' }
			2 { 'string:c3a9f09f98802665cc81' }
			3, 4, 5, 6 { 'non-string' }
			10 { 'string:' + 'org.vinix.binary'.bytes().hex() }
			else { 'nil' }
		}
		match i {
			3 { assert a.msg(result, c'longLongValue', 0, 0, 0) == 42 }
			4 { assert a.msg(result, c'boolValue', 0, 0, 0) == 1 }
			5 {
				assert a.msg(result, c'count', 0, 0, 0) == 1
				item := a.msg(result, c'objectAtIndex:', 0, 0, 0)
				assert unsafe { (&char(a.msg(item, c'UTF8String', 0, 0, 0))).vstring() } == 'x'
			}
			6 {
				assert a.msg(result, c'count', 0, 0, 0) == 1
				key := a.string('x')
				item := a.msg(result, c'objectForKey:', key, 0, 0)
				assert unsafe { (&char(a.msg(item, c'UTF8String', 0, 0, 0))).vstring() } == 'y'
				a.msg(key, c'release', 0, 0, 0)
			}
			else {}
		}
		os.write_file(plist_path, '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>changed</string></dict></plist>')!
		assert a.msg(bundle, c'bundleIdentifier', 0, 0, 0) == result
		println('case=' + i.str() + ' bundle=' + (bundle != 0).str() + ' result=' + output + ' cached=true')
		a.msg(name, c'release', 0, 0, 0)
	}
	println('IOS-BUNDLE-IDENTIFIER-ORACLE: eleven plist values and cached identity PASS')
}
