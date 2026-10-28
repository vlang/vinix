// SPDX-License-Identifier: GPL-2.0-or-later
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
fn C.method_getImplementation(voidptr) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.setxattr(&char, &char, voidptr, usize, u32, int) int
fn C.getxattr(&char, &char, voidptr, usize, u32, int) i64
type ResourceSend = fn (u64, voidptr, u64, u64, u64) u64
fn msg(object u64, selector &char, a u64, b u64, c u64) u64 {
	return unsafe { ResourceSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), a, b, c) }
}
fn cls(name &char) u64 { return u64(C.objc_getClass(name)) }
fn string_object(value string) u64 { return msg(cls(c'NSString'), c'stringWithUTF8String:', u64(value.str), 0, 0) }
fn text(object u64) string { return if object == 0 { '<nil>' } else { unsafe { cstring_to_vstring(&char(msg(msg(object, c'description', 0, 0, 0), c'UTF8String', 0, 0, 0))) } } }
fn query(url u64, key string) {
	mut value := u64(0x12345678)
	mut error_object := u64(0x12345678)
	ok := msg(url, c'getResourceValue:forKey:error:', u64(unsafe { &value }), string_object(key), u64(unsafe { &error_object }))
	println('${key}: ok=${ok} value=${if value == 0x12345678 { "untouched" } else { text(value) }} class=${if value == 0 || value == 0x12345678 { "-" } else { text(msg(value, c'className', 0, 0, 0)) }} error=${if error_object == 0x12345678 { "untouched" } else { text(error_object) }}')
}
fn main() {
	assert os.args.len == 2
	root := os.abs_path(os.args[1])
	assert !os.exists(root)
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or { panic(err) } }
	os.write_file(root + '/file', 'original')!
	os.mkdir(root + '/directory')!
	os.symlink(root + '/file', root + '/link')!
	os.symlink(root + '/missing', root + '/dangling')!
	pool := msg(cls(c'NSAutoreleasePool'), c'new', 0, 0, 0)
	method := C.class_getInstanceMethod(C.objc_getClass(c'NSURL'), C.sel_registerName(c'getResourceValue:forKey:error:'))
	println('types=${unsafe { cstring_to_vstring(C.method_getTypeEncoding(method)) }}')
	for path in [root + '/file', root + '/directory', root + '/link', root + '/missing', root + '/dangling', 'https://example.invalid/resource'] {
	println('PATH ${path}')
	url := if path.starts_with('https:') { msg(cls(c'NSURL'), c'URLWithString:', string_object(path), 0, 0) } else { msg(cls(c'NSURL'), c'fileURLWithPath:', string_object(path), 0, 0) }
	for key in ['NSURLFileSizeKey', 'NSURLIsRegularFileKey', 'NSURLCreationDateKey', 'NSURLIsExcludedFromBackupKey', 'NSURLVolumeAvailableCapacityForImportantUsageKey', 'NSURLVolumeAvailableCapacityKey', 'NSURLVolumeTotalCapacityKey', 'VinixUnknownKey'] {
		query(url, key)
	}
	if os.is_file(path) && !os.is_link(path) {
		original := os.read_file(path)!
		os.write_file(path, original + 'changed')!
		query(url, 'NSURLFileSizeKey')
		fresh := msg(cls(c'NSURL'), c'fileURLWithPath:', string_object(path), 0, 0)
		query(fresh, 'NSURLFileSizeKey')
		msg(url, c'removeCachedResourceValueForKey:', string_object('NSURLFileSizeKey'), 0, 0)
		query(url, 'NSURLFileSizeKey')
		os.write_file(path, original)!
		msg(url, c'removeAllCachedResourceValues', 0, 0, 0)
		query(url, 'NSURLFileSizeKey')
		backup := string_object('NSURLIsExcludedFromBackupKey')
		query(url, 'NSURLIsExcludedFromBackupKey')
		msg(url, c'setResourceValue:forKey:error:', msg(cls(c'NSNumber'), c'numberWithBool:', 1, 0, 0), backup, 0)
		query(url, 'NSURLIsExcludedFromBackupKey')
		query(msg(cls(c'NSURL'), c'fileURLWithPath:', string_object(root + '/link'), 0, 0), 'NSURLIsExcludedFromBackupKey')
		msg(url, c'setResourceValue:forKey:error:', msg(cls(c'NSNumber'), c'numberWithBool:', 0, 0, 0), backup, 0)
		query(url, 'NSURLIsExcludedFromBackupKey')
		link := msg(cls(c'NSURL'), c'fileURLWithPath:', string_object(root + '/link'), 0, 0)
		msg(link, c'removeAllCachedResourceValues', 0, 0, 0)
		query(link, 'NSURLIsExcludedFromBackupKey')
	}
	}
	for name in [c'removeCachedResourceValueForKey:', c'removeAllCachedResourceValues'] {
		m := C.class_getInstanceMethod(C.objc_getClass(c'NSURL'), C.sel_registerName(name))
		println('${unsafe { cstring_to_vstring(name) }} types=${unsafe { cstring_to_vstring(C.method_getTypeEncoding(m)) }}')
	}
	for i, payload in ['', 'com.apple.backupd', '<plist version="1.0"><string>other</string></plist>',
		'<plist version="1.0"><string>com.apple.backupd</string></plist>',
		'<plist version="1.0"><true/></plist>', '<plist version="1.0"><array><string>com.apple.backupd</string></array></plist>'] {
		path := root + '/attribute-' + i.str()
		os.write_file(path, 'attribute')!
		assert C.setxattr(path.str, c'com.apple.metadata:com_apple_backup_excludeItem', payload.str, usize(payload.len), 0, 0) == 0
		println('ATTRIBUTE ${i}: ${payload}')
		query(msg(cls(c'NSURL'), c'fileURLWithPath:', string_object(path), 0, 0), 'NSURLIsExcludedFromBackupKey')
	}
	setter_selector := C.sel_registerName(c'setResourceValue:forKey:error:')
	setter := C.method_getImplementation(C.class_getInstanceMethod(C.objc_getClass(c'NSURL'), setter_selector))
	for path in [root + '/file', root + '/directory', root + '/link'] {
		url := msg(cls(c'NSURL'), c'fileURLWithPath:', string_object(path), 0, 0)
		for flag in [false, true, true, false, false] {
			value := msg(cls(c'NSNumber'), c'numberWithBool:', u64(flag), 0, 0)
			key := string_object('NSURLIsExcludedFromBackupKey')
			assert msg(url, c'setResourceValue:forKey:error:', value, key, 0) == 1
			println('SET ${path} ${flag}: ${C.getxattr(path.str, c"com.apple.metadata:com_apple_backup_excludeItem", unsafe { nil }, 0, 0, 0)}')
			fresh := msg(cls(c'NSURL'), c'fileURLWithPath:', string_object(path), 0, 0)
			assert unsafe { ResourceSend(setter)(fresh, setter_selector, value, key, 0) } == 1
			println('IMP ${path} ${flag}: ${C.getxattr(path.str, c"com.apple.metadata:com_apple_backup_excludeItem", unsafe { nil }, 0, 0, 0)}')
		}
	}
	msg(pool, c'drain', 0, 0, 0)
}
