// SPDX-License-Identifier: GPL-2.0-or-later
// Native Foundation oracle; synthetic bundles and observations stay external.
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
fn (a Api) cls(name &char) u64 { return u64(C.objc_getClass(name)) }
fn (a Api) string(text string) u64 {
	return a.msg(a.msg(a.cls(c'NSString'), c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(text.str), u64(text.len), 4)
}
fn main() {
	assert os.args.len == 2
	root := os.abs_path(os.args[1])
	assert !os.exists(root)
	os.mkdir_all(root)!
	a := Api{unsafe { Send(C.dlsym(voidptr(-2), c'objc_msgSend')) }}
	pool := a.msg(a.cls(c'NSAutoreleasePool'), c'new', 0, 0, 0)
	defer { a.msg(pool, c'drain', 0, 0, 0) }
	values := ['<dict><key>CFBundleIdentifier</key><string>é😀&amp;é</string><key>nested</key><dict><key>items</key><array><integer>42</integer><true/><real>1.5</real><data>AAH/</data><string>x</string></array></dict></dict>',
		'binary', '<dict/>', 'missing', 'malformed', '<array><string>x</string></array>',
		'<string>x</string>', '<dict><key>CFBundleIdentifier</key><integer>42</integer></dict>']
	for order in 0 .. 2 {
		for i, value in values {
			path := os.join_path(root, order.str() + '-' + i.str() + '.bundle')
			os.mkdir_all(path)!
			plist_path := path + '/Info.plist'
			if value != 'missing' {
				os.write_file(plist_path, if value == 'malformed' { 'not a plist' } else {
					'<?xml version="1.0"?><plist version="1.0">' + if value == 'binary' { values[0] } else { value } + '</plist>'
				})!
				if value == 'binary' {
					assert os.exec(['/usr/bin/plutil', '-convert', 'binary1', plist_path]).exit_code == 0
					println('binary=' + os.read_bytes(plist_path)!.hex())
				}
			}
			name := a.string(path)
			bundle := a.msg(a.cls(c'NSBundle'), c'bundleWithPath:', name, 0, 0)
			assert bundle != 0
			first := a.msg(bundle, if order == 0 { c'infoDictionary' } else { c'bundleIdentifier' }, 0, 0, 0)
			os.write_file(plist_path, '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>changed</string></dict></plist>')!
			dict := a.msg(bundle, c'infoDictionary', 0, 0, 0)
			identifier := a.msg(bundle, c'bundleIdentifier', 0, 0, 0)
			key := a.string('CFBundleIdentifier')
			item := a.msg(dict, c'objectForKey:', key, 0, 0)
			count := a.msg(dict, c'count', 0, 0, 0)
			mutable := a.msg(dict, c'isKindOfClass:', a.cls(c'NSMutableDictionary'), 0, 0)
			println('order=' + order.str() + ' case=' + i.str() + ' present=' + (dict != 0).str() + ' count=' + count.str() + ' mutable=' + mutable.str() + ' identifier_shared=' + (item == identifier).str() + ' first_cached=' + (first == if order == 0 { dict } else { identifier }).str())
			assert a.msg(bundle, c'infoDictionary', 0, 0, 0) == dict
			assert dict != 0 && mutable == 1 && item == identifier
			assert count == if i < 2 { u64(2) } else if i == 7 { u64(1) } else { u64(0) }
			assert first == if order == 0 { dict } else { identifier }
			if i < 2 {
				nested_key := a.string('nested'); items_key := a.string('items')
				nested := a.msg(dict, c'objectForKey:', nested_key, 0, 0)
				items := a.msg(nested, c'objectForKey:', items_key, 0, 0)
				println('nested_mutable=' + a.msg(nested, c'isKindOfClass:', a.cls(c'NSMutableDictionary'), 0, 0).str() + ' array_mutable=' + a.msg(items, c'isKindOfClass:', a.cls(c'NSMutableArray'), 0, 0).str())
				assert a.msg(nested, c'isKindOfClass:', a.cls(c'NSMutableDictionary'), 0, 0) == 1
				assert a.msg(items, c'isKindOfClass:', a.cls(c'NSMutableArray'), 0, 0) == 1
				assert a.msg(items, c'count', 0, 0, 0) == 5
				a.msg(nested_key, c'release', 0, 0, 0); a.msg(items_key, c'release', 0, 0, 0)
			}
			replacement := a.string('replacement')
			a.msg(dict, c'setObject:forKey:', replacement, key, 0)
			println('mutation_visible=' + (a.msg(bundle, c'bundleIdentifier', 0, 0, 0) == replacement).str())
			assert a.msg(bundle, c'bundleIdentifier', 0, 0, 0) == replacement
			a.msg(dict, c'removeObjectForKey:', key, 0, 0)
			assert a.msg(bundle, c'bundleIdentifier', 0, 0, 0) == 0
			a.msg(replacement, c'release', 0, 0, 0)
			a.msg(key, c'release', 0, 0, 0)
			a.msg(name, c'release', 0, 0, 0)
		}
	}
	println('IOS-BUNDLE-INFO-ORACLE: sixteen plist and property-order observations PASS')
}
