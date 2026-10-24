// SPDX-License-Identifier: GPL-2.0-or-later
// Measure the installed Apple implementation without importing attachment files.
module main

#flag -framework Foundation
#flag -framework UserNotifications
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
type Send = fn (u64, voidptr, u64, u64, u64, u64) u64
fn msg(object u64, selector &char, a u64, b u64, c u64, d u64) u64 {
	return unsafe { Send(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), a, b, c, d) }
}
fn main() {
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0, 0)
	cls := u64(C.objc_getClass(c'UNNotificationAttachment'))
	for _ in 0 .. 2 {
		object := msg(msg(cls, c'alloc', 0, 0, 0, 0), c'initWithIdentifier:URL:type:options:', 0, 0, 0, 0)
		println('EMPTY object=${object != 0}')
		for selector in [c'identifier', c'URL', c'type', c'options', c'userInfo', c'family']! {
			println('VALUE ${unsafe { selector.vstring() }}=${msg(object, selector, 0, 0, 0, 0)}')
		}
		for selector in [c'identifier', c'type']! {
			println('EMPTY-TEXT ${unsafe { selector.vstring() }}=${unsafe { (&char(msg(msg(object, selector, 0, 0, 0, 0), c'UTF8String', 0, 0, 0, 0))).vstring() }}')
		}
		println('EMPTY-URL ${unsafe { (&char(msg(msg(msg(object, c'URL', 0, 0, 0, 0), c'absoluteString', 0, 0, 0, 0), c'UTF8String', 0, 0, 0, 0))).vstring() }}')
		for selector in [c'copy', c'copyWithZone:']! {
			copy := msg(object, selector, 0, 0, 0, 0)
			println('COPY ${unsafe { selector.vstring() }} self=${copy == object}')
			msg(copy, c'release', 0, 0, 0, 0)
		}
		// Reading all words also records native zero padding and lock defaults.
		for offset := u64(8); offset < 64; offset += 8 { println('BODY ${offset}=${unsafe { *(&u64(object + offset)) }}') }
		msg(object, c'release', 0, 0, 0, 0)
	}
	for value in ['/tmp/vinix-attachment.png', 'https://example.invalid/a.png']! {
		input := msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(value.str), 0, 0, 0)
		url := msg(u64(C.objc_getClass(c'NSURL')), if value.starts_with('/') { c'fileURLWithPath:' } else { c'URLWithString:' }, input, 0, 0, 0)
		object := msg(msg(cls, c'alloc', 0, 0, 0, 0), c'initWithIdentifier:URL:type:options:', input, url, 0, 0)
		println('URL value=${value} retained=${url == msg(object, c'URL', 0, 0, 0, 0)} family=${msg(object, c'family', 0, 0, 0, 0)}')
		msg(object, c'release', 0, 0, 0, 0)
	}
	for value in ['', 'preview', 'é😀']! {
		input := msg(msg(u64(C.objc_getClass(c'NSMutableString')), c'alloc', 0, 0, 0, 0), c'initWithUTF8String:', u64(value.str), 0, 0, 0)
		object := msg(msg(cls, c'alloc', 0, 0, 0, 0), c'initWithIdentifier:URL:type:options:', input, 0, input, 0)
		msg(input, c'setString:', msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(c'changed'), 0, 0, 0), 0, 0, 0)
		msg(input, c'release', 0, 0, 0, 0)
		for selector in [c'identifier', c'type']! {
			stored := msg(object, selector, 0, 0, 0, 0)
			println('TEXT ${unsafe { selector.vstring() }} snapshot=${unsafe { (&char(voidptr(msg(stored, c'UTF8String', 0, 0, 0, 0)))).vstring() }}')
		}
		println('FAMILY ${value}=${msg(object, c'family', 0, 0, 0, 0)}')
		msg(object, c'release', 0, 0, 0, 0)
	}
	msg(pool, c'drain', 0, 0, 0, 0)
}
