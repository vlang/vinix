// SPDX-License-Identifier: GPL-2.0-or-later
// Measure defaults, nil normalization and value copying on the installed SDK.
module main

#flag -framework Foundation
#flag -framework UserNotifications
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
type Send = fn (u64, voidptr, u64) u64
type DoubleSend = fn (u64, voidptr, f64) f64
fn msg(object u64, name &char, arg u64) u64 {
	return unsafe { Send(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(name), arg) }
}
fn main() {
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
	for class_name in ['UNNotificationContent', 'UNMutableNotificationContent']! {
		object := msg(u64(C.objc_getClass(class_name.str)), c'new', 0)
		for name in ['attachments', 'badge', 'body', 'categoryIdentifier', 'launchImageName', 'sound', 'subtitle', 'threadIdentifier', 'title', 'summaryArgument', 'targetContentIdentifier', 'userInfo', 'filterCriteria']! {
			value := msg(object, name.str, 0)
			text := if value == 0 { '<nil>' } else { unsafe { (&char(voidptr(msg(msg(value, c'description', 0), c'UTF8String', 0)))).vstring() } }
			println('${class_name} ${name} ${text}')
			if class_name == 'UNMutableNotificationContent' {
				setter := 'set' + name[..1].to_upper() + name[1..] + ':'
				msg(object, setter.str, 0)
				println('NIL ${name} ${if msg(object, name.str, 0) == 0 { "nil" } else { "normalized" }}')
			}
		}
		println('SCALAR ${class_name} ${msg(object, c'summaryArgumentCount', 0)} ${msg(object, c'interruptionLevel', 0)}')
		if class_name == 'UNMutableNotificationContent' {
			for value in [u64(0), 8, u64(-1)]! {
				msg(object, c'setSummaryArgumentCount:', value); msg(object, c'setInterruptionLevel:', value)
				println('SETSCALAR ${value} ${msg(object, c'summaryArgumentCount', 0)} ${msg(object, c'interruptionLevel', 0)}')
			}
			for value in [-1.0, 0.5, 2.0] {
				unsafe { DoubleSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(c'setRelevanceScore:'), value) }
				actual := unsafe { DoubleSend(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(c'relevanceScore'), 0.0) }
				println('RELEVANCE ${value} ${actual}')
			}
		}
		copy := msg(object, c'copy', 0); mutable := msg(object, c'mutableCopy', 0)
		println('COPY ${class_name} self=${copy == object} immutable=${msg(copy, c'isMemberOfClass:', u64(C.objc_getClass(c'UNNotificationContent')))} mutable=${msg(mutable, c'isMemberOfClass:', u64(C.objc_getClass(c'UNMutableNotificationContent')))}')
		msg(copy, c'release', 0); msg(mutable, c'release', 0); msg(object, c'release', 0)
	}
	object := msg(u64(C.objc_getClass(c'UNMutableNotificationContent')), c'new', 0)
	for name in ['body', 'categoryIdentifier', 'launchImageName', 'subtitle', 'threadIdentifier', 'title', 'summaryArgument', 'targetContentIdentifier', 'filterCriteria']! {
		setter := 'set' + name[..1].to_upper() + name[1..] + ':'
		input := msg(msg(u64(C.objc_getClass(c'NSMutableString')), c'alloc', 0), c'initWithUTF8String:', u64(c'original'))
		msg(object, setter.str, input)
		before := msg(object, name.str, 0)
		early_copy := msg(object, c'copy', 0)
		early_mutable := msg(object, c'mutableCopy', 0)
		msg(input, c'setString:', msg(u64(C.objc_getClass(c'NSString')), c'stringWithUTF8String:', u64(c'changed')))
		msg(input, c'release', 0)
		value := msg(object, name.str, 0)
		copy := msg(object, c'copy', 0)
		copied := msg(copy, name.str, 0)
		for cloned in [early_copy, early_mutable]! {
			value_copy := msg(cloned, name.str, 0)
			println('EARLYCOPY ${name} ${unsafe { (&char(voidptr(msg(value_copy, c'UTF8String', 0)))).vstring() }}')
			msg(cloned, c'release', 0)
		}
		println('MUTATION ${name} getter_before=${unsafe { (&char(voidptr(msg(before, c'UTF8String', 0)))).vstring() }} getter_after=${unsafe { (&char(voidptr(msg(value, c'UTF8String', 0)))).vstring() }} copy=${unsafe { (&char(voidptr(msg(copied, c'UTF8String', 0)))).vstring() }}')
		msg(copy, c'release', 0)
	}
	msg(object, c'release', 0)
	msg(pool, c'drain', 0)
}
